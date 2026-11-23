"""Pure approval state machine for remote promotion."""
import fcntl
import hashlib
import hmac
import json
import os
import re
import secrets
import struct
import time

ID = r'p[0-9]+-[0-9a-f]{8}'
SHA = r'(?:[0-9a-f]{40}|[0-9a-f]{64})'
TAG = r'hub-promote/[0-9]{8}T[0-9]{6}Z'
USER = r'(?:[A-Z0-9]{2,32}|cli)'
MOVERS = frozenset(('not_contained', 'not_newest_branch', 'not_green', 'not_newest_green', 'release_moved', 'tag_exists', 'deploy_moved', 'witness_conflict'))
FINAL = frozenset(('denied', 'expired', 'refused', 'consumed'))

class Refused(Exception):
    def __init__(self, code, message='', approval='final'):
        super().__init__(message or code)
        self.code, self.message, self.approval = code, message or code, approval

class Unknown(Exception):
    def __init__(self, code, message=''):
        super().__init__(message or code)
        self.code, self.message = code, message or code

def to_wire(value):
    if isinstance(value, Refused):
        result, code, message, data = 'refused', value.code, value.message, {'approval': value.approval}
    elif isinstance(value, Unknown):
        result, code, message, data = 'unknown', value.code, value.message, {}
    else:
        result, code, message, data = 'ok', 'ok', 'ok', value
    return json.dumps({'v': 1, 'result': result, 'code': code, 'message': message, 'data': data}, separators=(',', ':'))

def exit_code(wire_obj):
    if wire_obj['result'] == 'ok':
        return 0
    if wire_obj['result'] == 'refused':
        return 2 if wire_obj['code'] == 'bad_input' else 1
    return 75

class SystemClock:
    def now(self):
        return int(time.time())

class FileClock:
    def __init__(self, path):
        self.path = path
    def now(self):
        with open(self.path, encoding='ascii') as f:
            return int(f.read())

def totp_code(secret, now):
    digest = hmac.new(secret, struct.pack('>Q', now // 30), hashlib.sha1).digest()
    offset = digest[-1] & 15
    return '%06d' % ((struct.unpack('>I', digest[offset:offset + 4])[0] & 0x7fffffff) % 1000000)

def check_value(id, sha):
    digest = hashlib.sha256(('k3dm-promote-check:v1\n' + id + '\n' + sha).encode('ascii')).digest()
    n = int.from_bytes(digest[:3], 'big') >> 4
    alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
    return ''.join(alphabet[(n >> (15 - 5 * k)) & 31] for k in range(4))

def approval_mac(key, id, nonce, approver, check, totp, at):
    data = 'k3dm-promote-approve:v1\n' + '\n'.join((id, nonce, approver, check, totp, at)) + '\n'
    return hmac.new(key, data.encode('ascii'), hashlib.sha256).hexdigest()

def _matches(pattern, value):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None

def _integer(value, minimum=0, maximum=None):
    return type(value) is int and value >= minimum and (maximum is None or value <= maximum)

def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('ascii')

def _sealed(value):
    value = dict(value)
    value['sum'] = hashlib.sha256(_canonical(value)).hexdigest()
    return value

def _valid_attempt(a):
    return isinstance(a, dict) and set(a) == {'tag', 'object', 'old'} and _matches(TAG, a['tag']) and _matches(SHA, a['object']) and _matches(SHA, a['old'])

def _valid_record(r, id):
    fields = {'schema','id','sha','branch','nonce_sha256','channel','requested_by','created','expires','state','approver','approved_at','totp_step','failed_attempts','reason','refusals','push_at','old','new','tag','consumed_at','attempt'}
    if set(r) != fields:
        return False
    nullable_int = lambda v: v is None or _integer(v)
    nullable_sha = lambda v: v is None or _matches(SHA, v)
    return (r['schema'] == 1 and type(r['schema']) is int and r['id'] == id and _matches(ID, id)
            and _matches(SHA, r['sha']) and _matches(r'k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+', r['branch'])
            and _matches(r'[0-9a-f]{64}', r['nonce_sha256']) and r['channel'] in ('cloud-session','slack-alert','cli')
            and _matches(r'[A-Za-z0-9._:@-]{1,64}', r['requested_by']) and _integer(r['created'])
            and _integer(r['expires']) and r['expires'] == r['created'] + 900
            and r['state'] in FINAL | {'pending','approved'} and (r['approver'] is None or _matches(USER, r['approver']))
            and nullable_int(r['approved_at']) and nullable_int(r['totp_step']) and _integer(r['failed_attempts'], 0, 5)
            and (r['reason'] is None or r['reason'] in MOVERS | {'malformed_id','not_found','integrity','not_pending','not_approved','expired','clock_backwards','locked','nonce','approver','check','early_code','totp','too_many_codes','sha_mismatch','already_spent','state_lost','rate_limited','bad_input','signature','envelope_stale'})
            and _integer(r['refusals']) and nullable_int(r['push_at']) and nullable_sha(r['old']) and nullable_sha(r['new'])
            and (r['tag'] is None or _matches(TAG, r['tag'])) and nullable_int(r['consumed_at'])
            and (r['attempt'] is None or _valid_attempt(r['attempt'])))

class Engine:
    def __init__(self, state_dir, clock, totp_secret, operator_ids, relay_key):
        self.directory, self.clock, self.secret, self.operators, self.key = os.fspath(state_dir), clock, totp_secret, operator_ids, relay_key

    def _safe(self):
        try:
            s = os.stat(self.directory)
            if not os.path.isdir(self.directory) or s.st_uid != os.geteuid() or (s.st_mode & 0o7777) != 0o700:
                raise Unknown('state_dir_unsafe')
        except OSError:
            raise Unknown('state_dir_unsafe')

    def _read(self, name, kind):
        try:
            with open(os.path.join(self.directory, name), encoding='utf-8') as f:
                obj = json.load(f)
            if not isinstance(obj, dict):
                raise ValueError()
            checksum = obj.pop('sum', None)
            if not isinstance(checksum, str) or not hmac.compare_digest(checksum, hashlib.sha256(_canonical(obj)).hexdigest()):
                raise ValueError()
            if kind == 'record':
                valid = _valid_record(obj, name[:-5])
            elif kind == 'serial':
                valid = set(obj) == {'next'} and _integer(obj['next'], 1)
            elif kind == 'clock':
                valid = set(obj) == {'hw'} and _integer(obj['hw'])
            else:
                valid = set(obj) == {'last_step','fail_count','window_start','locked_until'} and _integer(obj['last_step']) and _integer(obj['fail_count'], 0, 10) and _integer(obj['window_start']) and _integer(obj['locked_until'])
            if not valid:
                raise ValueError()
            return obj
        except FileNotFoundError:
            raise Refused('not_found')
        except (ValueError, TypeError, KeyError, UnicodeError, json.JSONDecodeError):
            raise Refused('integrity')

    def _replace(self, name, obj):
        path = os.path.join(self.directory, name)
        fd = os.open(path + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            os.fchmod(fd, 0o600)
            data = _canonical(_sealed(obj))
            with os.fdopen(fd, 'wb') as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
        except BaseException:
            raise
        os.replace(path + '.tmp', path)
        fd = os.open(self.directory, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def _audit(self, event, now, id, sha, channel, actor, outcome):
        path = os.path.join(self.directory, 'audit.jsonl')
        if os.path.exists(path) and os.stat(path).st_size > 1048576:
            os.replace(path, os.path.join(self.directory, 'audit.1.jsonl'))
        line = {'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now)), 'event': event, 'id': id, 'sha7': sha[:7] if sha else None, 'channel': channel, 'actor': actor, 'result': 'refused' if isinstance(outcome, Refused) else 'ok', 'code': outcome.code if isinstance(outcome, Refused) else 'ok'}
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            data = _canonical(line) + b'\n'
            if os.write(fd, data) != len(data):
                raise OSError('short audit write')
            os.fsync(fd)
        finally:
            os.close(fd)

    def show(self, id):
        self._safe()
        self._id(id)
        try:
            r = self._read(id + '.json', 'record')
            keys = ('id','state','sha','branch','channel','requested_by','created','expires','approver','approved_at','reason','refusals','push_at','old','new','tag')
            out = {k: r[k] for k in keys}
            if r['state'] not in FINAL and r['push_at'] is None and self.clock.now() >= r['expires']:
                out['state'] = 'expired'
            out['check'] = check_value(id, r['sha'])
            return out
        except OSError:
            raise Unknown('io')

    def _refusal_approval(self, id):
        if not _matches(ID, id):
            return 'final'
        try:
            record = self._read(id + '.json', 'record')
        except (Refused, OSError):
            return 'final'
        return 'final' if record['state'] in FINAL else 'kept'

    def _id(self, id):
        if not _matches(ID, id):
            raise Refused('malformed_id')

    def _call(self, event, id=None, sha=None, channel=None, actor=None, **args):
        self._safe()
        if self.secret is None or self.key is None:
            raise Unknown('unconfigured')
        if event == 'approve' and not isinstance(id, str):
            raise Refused('bad_input', approval='kept')
        if event != 'request':
            if event == 'approve' and not _matches(ID, id):
                raise Refused('malformed_id', approval='kept')
            self._id(id)
        def bad():
            approval = 'kept' if event == 'approve' else self._refusal_approval(id)
            raise Refused('bad_input', approval=approval)
        if event == 'request':
            if not (_matches(SHA, sha) and _matches(r'k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+', args['branch']) and channel in ('cloud-session','slack-alert','cli') and _matches(r'[A-Za-z0-9._:@-]{1,64}', actor)):
                bad()
        elif event == 'approve':
            if not (all(isinstance(x, str) for x in (id,args['nonce'],actor,args['totp'],args['check'],args['at'],args['sig'])) and _matches(r'[0-9a-f]{16}', args['nonce']) and _matches(USER, actor) and _matches(r'[0-9A-Za-z]{4}', args['check']) and _matches(r'[!-~]{1,16}', args['totp']) and _matches(r'[0-9]{10}', args['at'])):
                bad()
        elif event == 'deny':
            if not (_matches(r'[0-9a-f]{16}', args['nonce']) and _matches(USER, actor)):
                bad()
        elif event in ('begin_promote','authorize_push'):
            if not _matches(SHA, sha) or (event == 'authorize_push' and not _valid_attempt(args['attempt'])):
                bad()
        elif event == 'commit_moved':
            if not (_matches(SHA, args['old']) and _matches(SHA, args['new']) and _matches(TAG, args['tag'])):
                bad()
        elif event == 'note_refusal' and (not isinstance(args['code'], str) or args['code'] not in MOVERS):
            bad()
        try:
            fd = os.open(os.path.join(self.directory, '.lock'), os.O_CREAT | os.O_RDWR, 0o600)
            try:
                deadline = time.monotonic() + 5
                while True:
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.monotonic() >= deadline:
                            raise Unknown('busy')
                        time.sleep(0.05)
                return self._locked(event, id, sha, channel, actor, args)
            finally:
                os.close(fd)
        except OSError:
            raise Unknown('io')

    def _locked(self, event, id, sha, channel, actor, args):
        now = self.clock.now()
        requested_sha = sha
        records = [n for n in os.listdir(self.directory) if _matches(ID + r'\.json', n)]
        defaults = {'serial.json': ('serial', {'next': 1}), 'totp-state.json': ('totp', {'last_step': 0, 'fail_count': 0, 'window_start': 0, 'locked_until': 0}), 'clock-hw.json': ('clock', {'hw': now})}
        states, missing, writes, record = {}, [], [], None
        record_step = False
        try:
            for name, (kind, default) in defaults.items():
                try:
                    states[name] = self._read(name, kind)
                except Refused as exc:
                    if records:
                        raise Refused('state_lost', 'approval state was lost; re-enrol (Part 2c) before approving')
                    if exc.code != 'not_found':
                        raise
                    states[name] = default
                    missing.append(name)
            if now < states['clock-hw.json']['hw'] - 5:
                raise Refused('clock_backwards')
            if event == 'approve':
                sig = args['sig']
                if not _matches(r'[0-9a-f]{64}', sig) or not hmac.compare_digest(sig, approval_mac(self.key, id, args['nonce'], actor, args['check'], args['totp'], args['at'])):
                    raise Refused('signature', approval='kept')
                if not now - 300 <= int(args['at']) <= now + 120:
                    raise Refused('envelope_stale', approval='kept')
            if id is not None:
                record_step = True
                record = self._read(id + '.json', 'record')
                sha, channel = record['sha'], record['channel']
            outcome = self._decide(event, id, record, states, records, now, args, requested_sha, channel, actor, writes)
        except Refused as exc:
            outcome = exc
            if event == 'approve' and not record_step:
                exc.approval = 'kept'
            elif exc.code not in ('signature', 'envelope_stale'):
                if record is not None:
                    exc.approval = 'final' if record['state'] in FINAL else 'kept'
                elif exc.code in ('state_lost', 'clock_backwards') and id is not None:
                    try:
                        record = self._read(id + '.json', 'record')
                    except (Refused, OSError):
                        pass
                    else:
                        exc.approval = 'final' if record['state'] in FINAL else 'kept'
                        sha, channel = record['sha'], record['channel']
        self._audit(event, now, id, sha, channel, actor, outcome)
        if writes:
            states['clock-hw.json']['hw'] = max(now, states['clock-hw.json']['hw'])
            for name in missing:
                if name != 'clock-hw.json':
                    self._replace(name, states[name])
            self._replace('clock-hw.json', states['clock-hw.json'])
            for name, value in writes:
                self._replace(name, value)
        if isinstance(outcome, Refused):
            raise outcome
        return outcome

    def _decide(self, event, id, r, states, records, now, args, sha, channel, actor, writes):
        def save(record):
            writes.append((record['id'] + '.json', record))
        def refuse(code, message=''):
            raise Refused(code, message)
        def expire(record):
            if record['state'] not in FINAL and record['push_at'] is None and now >= record['expires']:
                record['state'] = 'expired'
                save(record)
                return True
            return False
        if event == 'request':
            all_records = []
            for name in records:
                item = self._read(name, 'record')
                expire(item)
                all_records.append(item)
            pending = next((x for x in all_records if x['state'] == 'pending'), None)
            if pending:
                refuse('rate_limited', 'pending approval ' + pending['id'])
            if any(x['state'] not in FINAL and x['sha'] == sha for x in all_records) or sum(x['created'] > now - 3600 for x in all_records) >= 3 or sum(x['state'] not in FINAL for x in all_records) >= 5:
                refuse('rate_limited')
            serial = states['serial.json']
            id = 'p%d-%s' % (serial['next'], secrets.token_hex(4))
            nonce = secrets.token_hex(8)
            r = {'schema': 1, 'id': id, 'sha': sha, 'branch': args['branch'], 'nonce_sha256': hashlib.sha256(nonce.encode('ascii')).hexdigest(), 'channel': channel, 'requested_by': actor, 'created': now, 'expires': now + 900, 'state': 'pending', 'approver': None, 'approved_at': None, 'totp_step': None, 'failed_attempts': 0, 'reason': None, 'refusals': 0, 'push_at': None, 'old': None, 'new': None, 'tag': None, 'consumed_at': None, 'attempt': None}
            serial['next'] += 1
            writes.append(('serial.json', serial))
            save(r)
            return {'id': id, 'nonce': nonce, 'expires': r['expires'], 'check': check_value(id, sha)}
        if event in ('begin_promote', 'commit_moved') and (sha if event == 'begin_promote' else args['new']) != r['sha']:
            refuse('sha_mismatch')
        if event == 'approve':
            if r['state'] != 'pending':
                expire(r)
                refuse('not_pending')
            if expire(r):
                refuse('expired')
            state = states['totp-state.json']
            if now < state['locked_until']:
                refuse('locked')
            if not hmac.compare_digest(hashlib.sha256(args['nonce'].encode('ascii')).hexdigest(), r['nonce_sha256']):
                refuse('nonce')
            if actor not in self.operators:
                refuse('approver')
            failure, step = None, None
            if not hmac.compare_digest(args['check'].upper(), check_value(id, r['sha'])):
                failure = 'check'
            else:
                if _matches(r'[0-9]{6}', args['totp']):
                    step = next((s for s in (now // 30 - 1, now // 30, now // 30 + 1) if s >= 0 and hmac.compare_digest(totp_code(self.secret, s * 30), args['totp'])), None)
                if step is None:
                    failure = 'totp'
                elif step <= r['created'] // 30:
                    failure = 'early_code'
                elif step <= state['last_step']:
                    failure = 'totp'
            if failure:
                if now - state['window_start'] >= 900:
                    state['window_start'], state['fail_count'] = now, 0
                state['fail_count'] += 1
                if state['fail_count'] >= 10:
                    state['locked_until'] = now + 900
                r['failed_attempts'] += 1
                if r['failed_attempts'] >= 5:
                    r['state'], r['reason'], failure = 'refused', 'too_many_codes', 'too_many_codes'
                writes.append(('totp-state.json', state))
                save(r)
                refuse(failure)
            state['last_step'], state['fail_count'] = step, 0
            r.update(state='approved', approver=actor, approved_at=now, totp_step=step)
            writes.append(('totp-state.json', state))
            save(r)
            return {'id': id, 'state': 'approved'}
        if event == 'deny':
            if r['state'] not in ('pending', 'approved') or r['push_at'] is not None:
                refuse('not_pending')
            if expire(r):
                refuse('expired')
            if not hmac.compare_digest(hashlib.sha256(args['nonce'].encode('ascii')).hexdigest(), r['nonce_sha256']):
                refuse('nonce')
            if actor not in self.operators:
                refuse('approver')
            r['state'] = 'denied'
            save(r)
            return {'id': id, 'state': 'denied'}
        if event == 'begin_promote':
            if r['state'] == 'consumed':
                return {'mode': 'consumed', 'record': r.copy()}
            if r['state'] != 'approved':
                expire(r)
                refuse('not_approved')
            if expire(r):
                refuse('expired')
            return {'mode': 'recover' if r['push_at'] is not None else 'fresh', 'record': r.copy()}
        if event == 'authorize_push':
            if r['state'] != 'approved' or r['push_at'] is not None:
                expire(r)
                refuse('not_approved')
            if sha != r['sha']:
                expire(r)
                refuse('sha_mismatch')
            if expire(r):
                refuse('expired')
            r['push_at'], r['attempt'] = now, dict(args['attempt'])
            save(r)
            return {'push_at': now}
        if event == 'note_refusal':
            if r['state'] != 'approved':
                expire(r)
                refuse('not_approved')
            if expire(r):
                refuse('expired')
            r['refusals'] += 1
            r.update(reason=args['code'], push_at=None, attempt=None)
            save(r)
            return {'id': id, 'state': 'approved'}
        if event == 'commit_moved':
            if r['state'] == 'consumed':
                if r['old'] != args['old'] or r['tag'] != args['tag']:
                    refuse('already_spent')
                return {'id': id, 'state': 'consumed'}
            if r['state'] != 'approved' or r['push_at'] is None:
                expire(r)
                refuse('not_approved')
            r.update(state='consumed', old=args['old'], new=args['new'], tag=args['tag'], consumed_at=now)
            save(r)
            return {'id': id, 'state': 'consumed'}
        if event == 'finish_unmoved':
            if r['state'] != 'approved' or r['push_at'] is None:
                expire(r)
                refuse('not_approved')
            r['push_at'], r['attempt'] = None, None
            if now >= r['expires']:
                r['state'] = 'expired'
            save(r)
            return {'id': id, 'state': r['state']}

    def request(self, sha, branch, channel, requested_by):
        return self._call('request', sha=sha, channel=channel, actor=requested_by, branch=branch)
    def approve(self, id, nonce, approver, totp, check, at, sig):
        return self._call('approve', id=id, actor=approver, nonce=nonce, totp=totp, check=check, at=at, sig=sig)
    def deny(self, id, nonce, approver):
        return self._call('deny', id=id, actor=approver, nonce=nonce)
    def begin_promote(self, id, sha):
        return self._call('begin_promote', id=id, sha=sha)
    def authorize_push(self, id, sha, attempt):
        return self._call('authorize_push', id=id, sha=sha, attempt=attempt)
    def note_refusal(self, id, code):
        return self._call('note_refusal', id=id, code=code)
    def commit_moved(self, id, old, new, tag):
        return self._call('commit_moved', id=id, old=old, new=new, tag=tag)
    def finish_unmoved(self, id):
        return self._call('finish_unmoved', id=id)
