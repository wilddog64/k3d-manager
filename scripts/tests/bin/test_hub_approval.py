import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import hub_approval

import hashlib
import json
import os
import pytest

SECRET = b'12345678901234567890'
KEY = bytes(range(32))
SHA = 'a' * 40
TAG = 'hub-promote/20261119T000000Z'

@pytest.fixture(autouse=True)
def scratch_home(tmp_path, monkeypatch):
    home = tmp_path / 'home'
    home.mkdir(mode=0o700)
    monkeypatch.setenv('HOME', str(home))
    assert os.environ['HOME'] == str(home) and home.is_dir()

@pytest.fixture
def setup(tmp_path):
    state = tmp_path / 'state'
    state.mkdir(mode=0o700)
    clock_path = tmp_path / 'clock'
    clock_path.write_text('1700000040')
    assert state.is_dir() and state.stat().st_mode & 0o777 == 0o700
    assert clock_path.read_text() == '1700000040'
    clock = hub_approval.FileClock(clock_path)
    return hub_approval.Engine(state, clock, SECRET, frozenset({'U0123ABCD'}), KEY), state, clock_path

def request(engine):
    return engine.request(SHA, 'k3d-manager-v1.45.0', 'cli', 'tester')

def approve(engine, card, now, sig=None, code=None, check=None):
    code = code or hub_approval.totp_code(SECRET, now)
    check = check or card['check']
    at = str(now)
    sig = sig if sig is not None else hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', check, code, at)
    return engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, check, at, sig)

def test_vectors():
    assert [hub_approval.totp_code(SECRET, t) for t in (59,1111111109,1111111111,1234567890,2000000000,20000000000)] == ['287082','081804','050471','005924','279037','353130']
    assert hub_approval.check_value('p1-0123abcd', SHA) == '03Q1'
    assert hub_approval.check_value('p1-0123abcd', 'b'*40) == 'KTR0'
    assert hub_approval.check_value('p2-0123abcd', SHA) == 'CJ9W'
    assert hub_approval.check_value('p7-deadbeef', '0123456789abcdef0123456789abcdef01234567') == 'N4ES'
    assert hub_approval.approval_mac(KEY, 'p1-0123abcd', '00112233aabbccdd', 'U0123ABCD', '03Q1', '287082', '1700000059') == '5f45ca7b5b3724c6b0d50e0600af206effbb5669d2fb86b530d9ba913d5d572e'
    assert hub_approval.approval_mac(KEY, 'p2-0123abcd', '00112233aabbccdd', 'U0123ABCD', '03Q1', '287082', '1700000059') == '799b39e7ee50769fe1347bd35435fb5fb31f40f696d1b2ca7ea149a6ad21c2ce'
    assert hub_approval.approval_mac(KEY, 'p1-0123abcd', '00112233aabbccdd', 'U0123ABCD', 'KTR0', '287082', '1700000059') == '4f306c720a47babf86b68f8123e0ef11c3801dd9b25852a4a33987ea7ca54d87'
    assert hub_approval.approval_mac(bytes(32), 'p1-0123abcd', '00112233aabbccdd', 'U0123ABCD', '03Q1', '287082', '1700000059') == '88c6897a91018fc0411e238afab1caca540e211888c55d6a3bb72c0bdf905626'

def test_happy_and_wrong_sha(setup):
    engine, state, clock = setup
    card = request(engine)
    assert json.loads((state / (card['id'] + '.json')).read_text())['nonce_sha256'] == hashlib.sha256(card['nonce'].encode()).hexdigest()
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    clock.write_text('1700000080')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused, match='sha_mismatch'):
        engine.begin_promote(card['id'], 'b' * 40)
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'fresh'
    engine.authorize_push(card['id'], SHA, {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40})
    clock.write_text('1700001000')
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'recover'
    engine.commit_moved(card['id'], 'b'*40, SHA, TAG)
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'consumed'

def test_forged_first_and_genuine(setup):
    engine, state, clock = setup
    with pytest.raises(hub_approval.Refused, match='signature'):
        engine.approve('p1-0123abcd', '0'*16, 'U0123ABCD', '123456', '03Q1', '1700000040', '')
    assert not list(state.glob('*.json'))
    card = request(engine)
    clock.write_text('1700000070')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    code = hub_approval.totp_code(SECRET, 1700000070)
    forged = hub_approval.approval_mac(bytes(32), card['id'], card['nonce'], 'U0123ABCD', card['check'], code, '1700000070')
    with pytest.raises(hub_approval.Refused, match='signature'):
        approve(engine, card, 1700000070, sig=forged)
    with pytest.raises(hub_approval.Refused, match='signature'):
        approve(engine, card, 1700000070, sig='0'*64)
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    approve(engine, card, 1700000070)
    assert engine.show(card['id'])['state'] == 'approved'

def test_early_then_valid(setup):
    engine, state, clock = setup
    card = request(engine)
    with pytest.raises(hub_approval.Refused, match='early_code'):
        approve(engine, card, 1700000040)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    assert engine.show(card['id'])['state'] == 'approved'

def test_integrity_and_show_read_only(setup):
    engine, state, clock = setup
    card = request(engine)
    path = state / (card['id'] + '.json')
    original = path.read_text()
    before = {p.name: p.stat().st_mtime_ns for p in state.iterdir()}
    assert engine.show(card['id'])['check'] == card['check']
    assert before == {p.name: p.stat().st_mtime_ns for p in state.iterdir()}
    obj = json.loads(original)
    obj['failed_attempts'] = 100
    del obj['sum']
    obj['sum'] = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()
    path.write_text(json.dumps(obj))
    with pytest.raises(hub_approval.Refused, match='integrity'):
        engine.show(card['id'])
    path.write_text(original)
    assert engine.show(card['id'])['state'] == 'pending'

def test_expiry_and_wrong_sha(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000940')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused, match='sha_mismatch'):
        engine.begin_promote(card['id'], 'b'*40)
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    assert engine.show(card['id'])['state'] == 'expired'
    next_card = request(engine)
    assert next_card['id'] != card['id']
    assert json.loads((state / (card['id'] + '.json')).read_text())['state'] == 'expired'

def test_wrong_check_and_valid(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    check = 'ZZZZ' if card['check'] != 'ZZZZ' else 'YYYY'
    with pytest.raises(hub_approval.Refused, match='check'):
        approve(engine, card, 1700000070, check=check)
    assert json.loads((state / (card['id'] + '.json')).read_text())['failed_attempts'] == 1
    approve(engine, card, 1700000070)
    assert engine.show(card['id'])['state'] == 'approved'

def test_state_loss_and_clock_rollback(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000034')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused, match='clock_backwards'):
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    clock.write_text('1700000040')
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'
    (state / 'serial.json').unlink()
    with pytest.raises(hub_approval.Refused, match='approval state was lost') as exc:
        request(engine)
    assert exc.value.code == 'state_lost'

def test_five_failures_and_deny(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    check = 'ZZZZ' if card['check'] != 'ZZZZ' else 'YYYY'
    for count in range(5):
        with pytest.raises(hub_approval.Refused) as exc:
            approve(engine, card, 1700000070, check=check)
        assert exc.value.code == ('too_many_codes' if count == 4 else 'check')
    assert engine.show(card['id'])['state'] == 'refused'
    next_card = request(engine)
    engine.deny(next_card['id'], next_card['nonce'], 'U0123ABCD')
    assert engine.show(next_card['id'])['state'] == 'denied'

def test_wire():
    for value, result, code, data in [({}, 'ok', 'ok', {}), (hub_approval.Refused('signature', approval='kept'), 'refused', 'signature', {'approval': 'kept'}), (hub_approval.Unknown('busy'), 'unknown', 'busy', {})]:
        wire = json.loads(hub_approval.to_wire(value))
        assert set(wire) == {'v', 'result', 'code', 'message', 'data'}
        assert (wire['result'], wire['code'], wire['data']) == (result, code, data)

def test_crash_burns_totp_step(setup, monkeypatch):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    replace = engine._replace
    def crash(name, value):
        if name == card['id'] + '.json':
            raise OSError('injected crash')
        return replace(name, value)
    monkeypatch.setattr(engine, '_replace', crash)
    with pytest.raises(hub_approval.Unknown, match='io'):
        approve(engine, card, 1700000070)
    monkeypatch.setattr(engine, '_replace', replace)
    assert engine.show(card['id'])['state'] == 'pending'
    assert json.loads((state / 'totp-state.json').read_text())['last_step'] == 1700000070 // 30
    with pytest.raises(hub_approval.Refused, match='totp'):
        approve(engine, card, 1700000070)
    clock.write_text('1700000100')
    approve(engine, card, 1700000100)
    assert engine.show(card['id'])['state'] == 'approved'

def test_authorize_deadline(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    clock.write_text(str(card['expires']))
    attempt = {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40}
    with pytest.raises(hub_approval.Refused, match='expired'):
        engine.authorize_push(card['id'], SHA, attempt)
    assert engine.show(card['id'])['state'] == 'expired'

def test_no_environment_or_secret_leak(setup, tmp_path):
    engine, state, clock = setup
    assert Path(os.environ['HOME']) == tmp_path / 'home'
    assert engine.directory == str(state)
    card = request(engine)
    clock.write_text('1700000070')
    code = hub_approval.totp_code(SECRET, 1700000070)
    at = '1700000070'
    sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig)
    output = (state / (card['id'] + '.json')).read_text() + (state / 'audit.jsonl').read_text() + json.dumps(engine.show(card['id']))
    for secret in (card['nonce'], code, SECRET.decode(), KEY.hex(), sig):
        assert secret not in output
    assert hashlib.sha256(card['nonce'].encode()).hexdigest() in output
    assert card['check'] in output and SHA[:7] in output
    source = Path(hub_approval.__file__).read_text()
    for banned in ('subprocess', 'os.environ', 'os.getenv', 'socket'):
        assert banned not in source
    other = tmp_path / 'other'
    other.mkdir(mode=0o700)
    other_engine = hub_approval.Engine(other, hub_approval.FileClock(clock), SECRET, frozenset({'U0123ABCD'}), KEY)
    assert request(other_engine)['id'].startswith('p1-')
    assert engine.directory != other_engine.directory

def _parallel_approve(directory, clock_path, card, start, queue, step):
    import time
    engine = hub_approval.Engine(directory, hub_approval.FileClock(clock_path), SECRET, frozenset({'U0123ABCD'}), KEY)
    read = engine._read
    def slow_read(name, kind):
        value = read(name, kind)
        if kind == 'record':
            time.sleep(0.3)
        return value
    engine._read = slow_read
    now = 1700000070
    code = hub_approval.totp_code(SECRET, now + step * 30)
    start.wait()
    try:
        approve(engine, card, now, code=code)
        queue.put('ok')
    except hub_approval.Refused as exc:
        queue.put(exc.code)
    except hub_approval.Unknown as exc:
        queue.put('unknown:' + exc.code)

def test_concurrent_approvals(setup):
    import multiprocessing
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    ctx = multiprocessing.get_context('fork')
    start, queue = ctx.Event(), ctx.Queue()
    workers = [ctx.Process(target=_parallel_approve, args=(state, clock, card, start, queue, step)) for step in (0, 1)]
    for worker in workers:
        worker.start()
    start.set()
    results = [queue.get(timeout=10) for _ in workers]
    for worker in workers:
        worker.join(10)
        assert worker.exitcode == 0
    assert sorted(results) == ['not_pending', 'ok']
    assert engine.show(card['id'])['state'] == 'approved'

def test_signed_envelope_binding(setup):
    engine, state, clock = setup
    old = request(engine)
    clock.write_text('1700000070')
    code = hub_approval.totp_code(SECRET, 1700000070)
    at = '1700000070'
    old_sig = hub_approval.approval_mac(KEY, old['id'], old['nonce'], 'U0123ABCD', old['check'], code, at)
    clock.write_text('1700000040')
    engine.deny(old['id'], old['nonce'], 'U0123ABCD')
    new = request(engine)
    clock.write_text('1700000070')
    new_sig = hub_approval.approval_mac(KEY, new['id'], new['nonce'], 'U0123ABCD', new['check'], code, at)
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused, match='signature'):
        engine.approve(new['id'], old['nonce'], 'U0123ABCD', code, old['check'], at, old_sig)
    if old['check'] != new['check']:
        with pytest.raises(hub_approval.Refused, match='signature'):
            engine.approve(new['id'], new['nonce'], 'U0123ABCD', code, old['check'], at, new_sig)
    with pytest.raises(hub_approval.Refused, match='signature'):
        engine.approve(new['id'], new['nonce'], 'U0123ABCD', '000000', new['check'], at, '0'*64)
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    engine.approve(new['id'], new['nonce'], 'U0123ABCD', code, new['check'], at, new_sig)
    assert engine.show(new['id'])['state'] == 'approved'

@pytest.mark.parametrize('sig', ['', '0'*63, 'A'*64, 'é'*64, '0'*64])
def test_signature_rejected_without_writes(setup, sig):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused) as exc:
        approve(engine, card, 1700000070, sig=sig)
    assert (exc.value.code, exc.value.approval) == ('signature', 'kept')
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    assert json.loads((state / 'audit.jsonl').read_text().splitlines()[-1])['sha7'] is None
    approve(engine, card, 1700000070)

def test_envelope_freshness(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    code = hub_approval.totp_code(SECRET, 1700000070)
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    for timestamp in (1700000070-301, 1700000070+121):
        at = str(timestamp)
        sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
        with pytest.raises(hub_approval.Refused) as exc:
            engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig)
        assert (exc.value.code, exc.value.approval) == ('envelope_stale', 'kept')
        assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    at = str(1700000070-300)
    sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig)

def _parallel_commit(directory, clock_path, card, tag, start, queue):
    engine = hub_approval.Engine(directory, hub_approval.FileClock(clock_path), SECRET, frozenset({'U0123ABCD'}), KEY)
    start.wait()
    try:
        engine.commit_moved(card['id'], 'b'*40, SHA, tag)
        queue.put('ok')
    except hub_approval.Refused as exc:
        queue.put(exc.code)

def test_concurrent_commits(setup):
    import multiprocessing
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    engine.authorize_push(card['id'], SHA, {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40})
    ctx = multiprocessing.get_context('fork')
    start, queue = ctx.Event(), ctx.Queue()
    workers = [ctx.Process(target=_parallel_commit, args=(state, clock, card, tag, start, queue)) for tag in (TAG, 'hub-promote/20261119T000001Z')]
    for worker in workers:
        worker.start()
    start.set()
    results = [queue.get(timeout=10) for _ in workers]
    for worker in workers:
        worker.join(10)
        assert worker.exitcode == 0
    assert sorted(results) == ['already_spent', 'ok']

def test_busy_lock(setup):
    import fcntl
    engine, state, clock = setup
    card = request(engine)
    serial = state / 'serial.json'
    saved = serial.read_bytes()
    serial.unlink()
    with (state / '.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with pytest.raises(hub_approval.Unknown) as exc:
            engine.deny(card['id'], card['nonce'], 'U0123ABCD')
        assert exc.value.code == 'busy'
    with pytest.raises(hub_approval.Refused) as exc:
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert exc.value.code == 'state_lost'
    serial.write_bytes(saved)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'

def test_global_lock_and_deny(setup):
    engine, state, clock = setup
    first = request(engine)
    clock.write_text('1700000070')
    wrong = 'ZZZZ' if first['check'] != 'ZZZZ' else 'YYYY'
    for _ in range(5):
        with pytest.raises(hub_approval.Refused):
            approve(engine, first, 1700000070, check=wrong)
    second = request(engine)
    clock.write_text('1700000100')
    wrong = 'ZZZZ' if second['check'] != 'ZZZZ' else 'YYYY'
    for _ in range(5):
        with pytest.raises(hub_approval.Refused):
            approve(engine, second, 1700000100, check=wrong)
    third = request(engine)
    clock.write_text('1700000130')
    with pytest.raises(hub_approval.Refused, match='locked'):
        approve(engine, third, 1700000130)
    engine.deny(third['id'], third['nonce'], 'U0123ABCD')
    assert engine.show(third['id'])['state'] == 'denied'

def test_audit_rotation(setup):
    engine, state, clock = setup
    card = request(engine)
    audit = state / 'audit.jsonl'
    audit.write_bytes(b'x' * 1048577)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert (state / 'audit.1.jsonl').stat().st_size == 1048577
    lines = audit.read_text().splitlines()
    assert len(lines) == 1
    assert set(json.loads(lines[0])) == {'ts', 'event', 'id', 'sha7', 'channel', 'actor', 'result', 'code'}

@pytest.mark.parametrize('delay,expected', [(30, 'approved'), (31, 'totp')])
def test_delivery_deadline(setup, delay, expected):
    engine, state, clock = setup
    clock.write_text('1700000010')
    card = request(engine)
    step = 1700000040 // 30
    typed = step * 30 + 29
    clock.write_text(str(typed + delay))
    code = hub_approval.totp_code(SECRET, step * 30)
    if expected == 'totp':
        with pytest.raises(hub_approval.Refused, match='totp'):
            approve(engine, card, typed + delay, code=code)
    else:
        approve(engine, card, typed + delay, code=code)
        assert engine.show(card['id'])['state'] == 'approved'

def test_note_refusal_and_recovery(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    attempt = {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40}
    engine.authorize_push(card['id'], SHA, attempt)
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'recover'
    engine.note_refusal(card['id'], 'not_green')
    shown = engine.show(card['id'])
    assert (shown['state'], shown['reason'], shown['refusals'], shown['push_at']) == ('approved', 'not_green', 1, None)
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'fresh'
    with pytest.raises(hub_approval.Refused, match='bad_input'):
        engine.note_refusal(card['id'], 'already_spent')
    engine.authorize_push(card['id'], SHA, attempt)
    engine.finish_unmoved(card['id'])
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'fresh'

def test_unconfigured_and_input_precedence(setup):
    engine, state, clock = setup
    card = request(engine)
    for secret, key in ((None, KEY), (SECRET, None)):
        disabled = hub_approval.Engine(state, hub_approval.FileClock(clock), secret, frozenset({'U0123ABCD'}), key)
        assert disabled.show(card['id'])['state'] == 'pending'
        with pytest.raises(hub_approval.Unknown, match='unconfigured'):
            disabled.deny('bad/id', 'bad', 'bad')
    with pytest.raises(hub_approval.Refused) as exc:
        engine.deny('bad/id', 'bad', 'bad')
    assert exc.value.code == 'malformed_id'
    state.chmod(0o755)
    try:
        with pytest.raises(hub_approval.Unknown, match='state_dir_unsafe'):
            engine.deny('bad/id', 'bad', 'bad')
    finally:
        state.chmod(0o700)

def test_stale_envelope_precedes_record_read(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    code, at = hub_approval.totp_code(SECRET, 1700000070), '1699999769'
    missing = 'p999-01234567'
    sig = hub_approval.approval_mac(KEY, missing, card['nonce'], 'U0123ABCD', card['check'], code, at)
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(missing, card['nonce'], 'U0123ABCD', code, card['check'], at, sig)
    assert (exc.value.code, exc.value.approval) == ('envelope_stale', 'kept')
    approve(engine, card, 1700000070)

@pytest.mark.parametrize('field,bad', [('id', None), ('nonce', 'x'), ('approver', 'x'), ('totp', 'has space'), ('check', '***!'), ('at', '1'), ('sig', None)])
def test_approval_input_shape(setup, field, bad):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    code, at = hub_approval.totp_code(SECRET, 1700000070), '1700000070'
    args = {'id':card['id'], 'nonce':card['nonce'], 'approver':'U0123ABCD', 'totp':code, 'check':card['check'], 'at':at, 'sig':hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)}
    before = {p.name:p.read_bytes() for p in state.iterdir()}
    args[field] = bad
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(**args)
    assert exc.value.code == 'bad_input'
    assert before == {p.name:p.read_bytes() for p in state.iterdir()}
    approve(engine, card, 1700000070)

@pytest.mark.parametrize('filename,key,bad', [('serial.json','next',0), ('clock-hw.json','hw',-1), ('totp-state.json','fail_count',11)])
def test_singleton_integrity(setup, filename, key, bad):
    engine, state, clock = setup
    card = request(engine)
    path = state / filename
    original = path.read_bytes()
    obj = json.loads(original)
    obj[key] = bad
    del obj['sum']
    obj['sum'] = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()
    path.write_text(json.dumps(obj))
    with pytest.raises(hub_approval.Refused) as exc:
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert exc.value.code == 'state_lost'
    path.write_bytes(original)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'

def test_each_record_field_shape(setup):
    engine, state, clock = setup
    card = request(engine)
    path = state / (card['id'] + '.json')
    original = json.loads(path.read_text())
    bad_values = {'schema': 2, 'id': 'p2-01234567', 'sha':'x', 'branch':'main', 'nonce_sha256':'x', 'channel':'x', 'requested_by':'!', 'created':-1, 'expires':-1, 'state':'x', 'approver':'x', 'approved_at':-1, 'totp_step':-1, 'failed_attempts':6, 'reason':'x', 'refusals':-1, 'push_at':-1, 'old':'x', 'new':'x', 'tag':'x', 'consumed_at':-1, 'attempt':{}}
    assert engine.show(card['id'])['state'] == 'pending'
    for field, bad in bad_values.items():
        for recompute in (False, True):
            obj = dict(original)
            obj[field] = bad
            if recompute:
                del obj['sum']
                obj['sum'] = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()
            path.write_text(json.dumps(obj))
            with pytest.raises(hub_approval.Refused, match='integrity'):
                engine.show(card['id'])
    path.write_text(json.dumps(original))
    assert engine.show(card['id'])['state'] == 'pending'

def test_note_refusal_rejects_non_string(setup):
    engine, state, clock = setup
    card = request(engine)
    with pytest.raises(hub_approval.Refused) as exc:
        engine.note_refusal(card['id'], [])
    assert exc.value.code == 'bad_input'
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')

def test_clock_within_tolerance(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000035')
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'
    assert json.loads((state / 'clock-hw.json').read_text())['hw'] == 1700000040

def test_commit_wrong_sha_and_replay(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    engine.authorize_push(card['id'], SHA, {'tag':TAG, 'object':'c'*40, 'old':'b'*40})
    clock.write_text('1700000080')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused, match='sha_mismatch'):
        engine.commit_moved(card['id'], 'b'*40, 'c'*40, TAG)
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    engine.commit_moved(card['id'], 'b'*40, SHA, TAG)
    engine.commit_moved(card['id'], 'b'*40, SHA, TAG)
    with pytest.raises(hub_approval.Refused, match='already_spent'):
        engine.commit_moved(card['id'], 'c'*40, SHA, TAG)

def test_approval_order(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    at = '1700000070'
    code = 'xxxxxx'
    nonce = '0'*16
    actor = 'UOTHER'
    check = 'ZZZZ' if card['check'] != 'ZZZZ' else 'YYYY'
    def send(nonce, actor, check, code):
        sig = hub_approval.approval_mac(KEY, card['id'], nonce, actor, check, code, at)
        return engine.approve(card['id'], nonce, actor, code, check, at, sig)
    with pytest.raises(hub_approval.Refused) as exc:
        send(nonce, actor, check, code)
    assert exc.value.code == 'nonce'
    with pytest.raises(hub_approval.Refused) as exc:
        send(card['nonce'], actor, check, code)
    assert exc.value.code == 'approver'
    with pytest.raises(hub_approval.Refused) as exc:
        send(card['nonce'], 'U0123ABCD', check, code)
    assert exc.value.code == 'check'
    with pytest.raises(hub_approval.Refused) as exc:
        send(card['nonce'], 'U0123ABCD', card['check'], code)
    assert exc.value.code == 'totp'
    approve(engine, card, 1700000070)
    with pytest.raises(hub_approval.Refused) as exc:
        send(nonce, actor, check, code)
    assert exc.value.code == 'not_pending'

def test_approve_nonpending_lazily_expires(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    clock.write_text(str(card['expires']))
    with pytest.raises(hub_approval.Refused) as exc:
        approve(engine, card, card['expires'])
    assert exc.value.code == 'not_pending'
    assert json.loads((state / (card['id'] + '.json')).read_text())['state'] == 'expired'

def test_audit_append_failure_does_not_write_state(setup, monkeypatch):
    engine, state, clock = setup
    before = set(state.iterdir())
    def short_write(fd, data):
        return 0
    monkeypatch.setattr(hub_approval.os, 'write', short_write)
    with pytest.raises(hub_approval.Unknown) as exc:
        request(engine)
    assert exc.value.code == 'io'
    assert not list(state.glob('*.json'))
    assert before <= set(state.iterdir())

def test_request_rate_limits(setup):
    engine, state, clock = setup
    first = request(engine)
    with pytest.raises(hub_approval.Refused, match=first['id']) as exc:
        request(engine)
    assert exc.value.code == 'rate_limited'
    engine.deny(first['id'], first['nonce'], 'U0123ABCD')
    for _ in range(2):
        card = request(engine)
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    with pytest.raises(hub_approval.Refused, match='rate_limited'):
        request(engine)
    clock.write_text('1700003641')
    assert request(engine)['id'] != first['id']

def test_total_limit_counts_recorded_pushes(setup):
    engine, state, clock = setup
    for index in range(5):
        now = 1700000040 + index * 3600
        clock.write_text(str(now))
        sha = format(index + 1, '040x')
        card = engine.request(sha, 'k3d-manager-v1.45.0', 'cli', 'tester')
        clock.write_text(str(now + 30))
        approve(engine, card, now + 30)
        engine.authorize_push(card['id'], sha, {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40})
    clock.write_text(str(1700000040 + 5 * 3600))
    with pytest.raises(hub_approval.Refused, match='rate_limited'):
        engine.request('f'*40, 'k3d-manager-v1.45.0', 'cli', 'tester')
    assert engine.begin_promote(card['id'], sha)['mode'] == 'recover'

def test_failure_window_resets_and_success_clears(setup):
    engine, state, clock = setup
    first = request(engine)
    clock.write_text('1700000070')
    wrong = 'ZZZZ' if first['check'] != 'ZZZZ' else 'YYYY'
    with pytest.raises(hub_approval.Refused, match='check'):
        approve(engine, first, 1700000070, check=wrong)
    clock.write_text('1700000970')
    second = request(engine)
    clock.write_text('1700001000')
    wrong = 'ZZZZ' if second['check'] != 'ZZZZ' else 'YYYY'
    with pytest.raises(hub_approval.Refused, match='check'):
        approve(engine, second, 1700001000, check=wrong)
    throttle = json.loads((state / 'totp-state.json').read_text())
    assert throttle['fail_count'] == 1 and throttle['window_start'] == 1700001000
    approve(engine, second, 1700001000)
    assert json.loads((state / 'totp-state.json').read_text())['fail_count'] == 0

@pytest.mark.parametrize('kind', ['check', 'early_code', 'totp'])
def test_failure_kinds_reach_record_and_global_limits(setup, kind):
    engine, state, clock = setup
    now = 1700000040
    for record_number in range(2):
        card = request(engine)
        wrong_check = 'ZZZZ' if card['check'] != 'ZZZZ' else 'YYYY'
        for failure in range(5):
            code = 'xxxxxx' if kind == 'totp' else hub_approval.totp_code(SECRET, now)
            check = wrong_check if kind == 'check' else card['check']
            with pytest.raises(hub_approval.Refused) as exc:
                approve(engine, card, now, code=code, check=check)
            assert exc.value.code == ('too_many_codes' if failure == 4 else kind)
        assert engine.show(card['id'])['state'] == 'refused'
        assert json.loads((state / 'totp-state.json').read_text())['fail_count'] == (record_number + 1) * 5
    card = request(engine)
    with pytest.raises(hub_approval.Refused, match='locked'):
        approve(engine, card, now)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'

@pytest.mark.parametrize('offset', [-300, 120])
def test_envelope_freshness_inclusive_bounds(setup, offset):
    engine, state, clock = setup
    card = request(engine)
    now = 1700000070
    clock.write_text(str(now))
    code, at = hub_approval.totp_code(SECRET, now), str(now + offset)
    sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig)
    assert engine.show(card['id'])['state'] == 'approved'

@pytest.mark.parametrize('step_offset', [-1, 0, 1])
def test_each_totp_window_step(setup, step_offset):
    engine, state, clock = setup
    card = request(engine)
    now = 1700000100
    clock.write_text(str(now))
    code = hub_approval.totp_code(SECRET, now + 30 * step_offset)
    approve(engine, card, now, code=code, check=card['check'].lower())
    assert engine.show(card['id'])['state'] == 'approved'

def test_show_does_not_read_corrupt_singleton(setup):
    engine, state, clock = setup
    card = request(engine)
    (state / 'serial.json').write_text('broken')
    assert engine.show(card['id'])['state'] == 'pending'
    with pytest.raises(hub_approval.Refused, match='approval state was lost'):
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')

def test_deny_approved_revocation_and_push_guard(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'
    next_card = request(engine)
    clock.write_text('1700000100')
    approve(engine, next_card, 1700000100)
    engine.authorize_push(next_card['id'], SHA, {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40})
    with pytest.raises(hub_approval.Refused, match='not_pending'):
        engine.deny(next_card['id'], next_card['nonce'], 'U0123ABCD')
    assert engine.show(next_card['id'])['state'] == 'approved'

@pytest.mark.parametrize('filename', ['serial.json', 'totp-state.json', 'clock-hw.json'])
def test_missing_singletons_fail_closed(setup, filename):
    engine, state, clock = setup
    card = request(engine)
    path = state / filename
    original = path.read_bytes()
    path.unlink()
    assert engine.show(card['id'])['state'] == 'pending'
    with pytest.raises(hub_approval.Refused) as exc:
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert exc.value.code == 'state_lost'
    path.write_bytes(original)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')

def test_corrupt_record_key_sets_and_filename_binding(setup):
    engine, state, clock = setup
    card = request(engine)
    path = state / (card['id'] + '.json')
    original = json.loads(path.read_text())
    assert engine.show(card['id'])['state'] == 'pending'
    for alteration in ('extra', 'missing', 'checksum', 'truncated'):
        value = dict(original)
        if alteration == 'extra':
            value['unexpected'] = 1
        elif alteration == 'missing':
            del value['branch']
        elif alteration == 'checksum':
            del value['sum']
        if alteration in ('extra', 'missing'):
            del value['sum']
            value['sum'] = hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()
        path.write_text('{' if alteration == 'truncated' else json.dumps(value))
        with pytest.raises(hub_approval.Refused, match='integrity'):
            engine.show(card['id'])
    path.write_text(json.dumps(original))
    other_id = 'p99-01234567'
    path.rename(state / (other_id + '.json'))
    with pytest.raises(hub_approval.Refused, match='integrity'):
        engine.show(other_id)
    (state / (other_id + '.json')).rename(path)
    assert engine.show(card['id'])['state'] == 'pending'

def test_push_recovery_after_expiry_and_finish(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    clock.write_text(str(card['expires'] - 1))
    engine.authorize_push(card['id'], SHA, {'tag':TAG, 'object':'c'*40, 'old':'b'*40})
    clock.write_text(str(card['expires'] + 1))
    assert engine.begin_promote(card['id'], SHA)['mode'] == 'recover'
    engine.finish_unmoved(card['id'])
    assert engine.show(card['id'])['state'] == 'expired'

@pytest.mark.parametrize('event', ['request', 'approve', 'deny', 'begin_promote', 'authorize_push', 'note_refusal', 'commit_moved', 'finish_unmoved'])
def test_clock_rollback_precedes_each_locked_call(setup, event):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000034')
    at = '1700000034'
    code = hub_approval.totp_code(SECRET, int(at))
    sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    attempt = {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40}
    calls = {'request': lambda: request(engine), 'approve': lambda: engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig), 'deny': lambda: engine.deny(card['id'], card['nonce'], 'U0123ABCD'), 'begin_promote': lambda: engine.begin_promote(card['id'], SHA), 'authorize_push': lambda: engine.authorize_push(card['id'], SHA, attempt), 'note_refusal': lambda: engine.note_refusal(card['id'], 'not_green'), 'commit_moved': lambda: engine.commit_moved(card['id'], 'b'*40, SHA, TAG), 'finish_unmoved': lambda: engine.finish_unmoved(card['id'])}
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused) as exc:
        calls[event]()
    assert exc.value.code == 'clock_backwards'
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    clock.write_text('1700000040')
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'

def test_nonce_failures_do_not_spend_budget(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    now = 1700000070
    code, at = hub_approval.totp_code(SECRET, now), str(now)
    wrong = '0'*16 if card['nonce'] != '0'*16 else '1'*16
    for _ in range(10):
        sig = hub_approval.approval_mac(KEY, card['id'], wrong, 'U0123ABCD', card['check'], code, at)
        with pytest.raises(hub_approval.Refused, match='nonce'):
            engine.approve(card['id'], wrong, 'U0123ABCD', code, card['check'], at, sig)
    assert json.loads((state / 'totp-state.json').read_text())['fail_count'] == 0
    approve(engine, card, now)
    assert engine.show(card['id'])['state'] == 'approved'

def test_replayed_code_is_counted_across_records(setup):
    engine, state, clock = setup
    first = request(engine)
    now = 1700000070
    clock.write_text(str(now))
    code = hub_approval.totp_code(SECRET, now + 30)
    approve(engine, first, now, code=code)
    engine.deny(first['id'], first['nonce'], 'U0123ABCD')
    second = request(engine)
    with pytest.raises(hub_approval.Refused) as exc:
        approve(engine, second, now, code=code)
    assert exc.value.code == 'totp'
    assert json.loads((state / (second['id'] + '.json')).read_text())['failed_attempts'] == 1
    clock.write_text(str(now + 30))
    approve(engine, second, now + 30, code=hub_approval.totp_code(SECRET, now + 60))
    assert engine.show(second['id'])['state'] == 'approved'

def test_stale_card_and_unsigned_missing_id(setup):
    engine, state, clock = setup
    first = request(engine)
    now = 1700000070
    code, at = hub_approval.totp_code(SECRET, now), str(now)
    sig = hub_approval.approval_mac(KEY, first['id'], first['nonce'], 'U0123ABCD', first['check'], code, at)
    engine.deny(first['id'], first['nonce'], 'U0123ABCD')
    second = request(engine)
    clock.write_text(str(now))
    with pytest.raises(hub_approval.Refused) as stale:
        engine.approve(first['id'], first['nonce'], 'U0123ABCD', code, first['check'], at, sig)
    assert stale.value.code == 'not_pending'
    replies = []
    for id in (second['id'], 'p999-01234567'):
        with pytest.raises(hub_approval.Refused) as forged:
            engine.approve(id, second['nonce'], 'U0123ABCD', code, second['check'], at, '0'*64)
        replies.append(hub_approval.to_wire(forged.value))
    assert replies[0] == replies[1]
    approve(engine, second, now)
    assert engine.show(second['id'])['state'] == 'approved'

def test_clock_and_signature_precedence(setup):
    engine, state, clock = setup
    card = request(engine)
    serial = state / 'serial.json'
    saved = serial.read_bytes()
    serial.unlink()
    clock.write_text('1700000034')
    with pytest.raises(hub_approval.Refused) as exc:
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert exc.value.code == 'state_lost'
    serial.write_bytes(saved)
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(card['id'], card['nonce'], 'U0123ABCD', '123456', card['check'], '1700000034', '')
    assert exc.value.code == 'clock_backwards'
    clock.write_text('1700000040')
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(card['id'], card['nonce'], 'U0123ABCD', '123456', card['check'], '1699999000', '')
    assert exc.value.code == 'signature'
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    at, code = '1699999000', '123456'
    sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig)
    assert exc.value.code == 'envelope_stale'

def test_locked_nonce_and_early_replay_precedence(setup):
    engine, state, clock = setup
    card = request(engine)
    path = state / 'totp-state.json'
    original = json.loads(path.read_text())
    data = {k:v for k,v in original.items() if k != 'sum'}
    data['locked_until'] = 1700000100
    path.write_text(json.dumps(hub_approval._sealed(data)))
    now = 1700000040
    code, at = hub_approval.totp_code(SECRET, now), str(now)
    wrong = '0'*16 if card['nonce'] != '0'*16 else '1'*16
    sig = hub_approval.approval_mac(KEY, card['id'], wrong, 'U0123ABCD', card['check'], code, at)
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(card['id'], wrong, 'U0123ABCD', code, card['check'], at, sig)
    assert exc.value.code == 'locked'
    data['locked_until'], data['last_step'] = 0, now // 30
    path.write_text(json.dumps(hub_approval._sealed(data)))
    with pytest.raises(hub_approval.Refused) as exc:
        approve(engine, card, now)
    assert exc.value.code == 'early_code'
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    assert engine.show(card['id'])['state'] == 'approved'

def test_signature_precedes_wrong_totp(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused) as exc:
        approve(engine, card, 1700000070, code='xxxxxx', sig='0'*64)
    assert exc.value.code == 'signature'
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    approve(engine, card, 1700000070)
    assert engine.show(card['id'])['state'] == 'approved'

def test_corrupt_singleton_without_records_is_integrity(setup):
    engine, state, clock = setup
    path = state / 'serial.json'
    path.write_text('{')
    path.chmod(0o600)
    with pytest.raises(hub_approval.Refused) as exc:
        request(engine)
    assert exc.value.code == 'integrity'
    path.unlink()
    assert request(engine)['id'].startswith('p1-')

def test_every_singleton_shape_and_checksum(setup):
    engine, state, clock = setup
    card = request(engine)
    cases = {'serial.json': {'next': 0}, 'clock-hw.json': {'hw': -1}, 'totp-state.json': {'last_step': -1, 'fail_count': 11, 'window_start': -1, 'locked_until': -1}}
    for filename, values in cases.items():
        path = state / filename
        original = json.loads(path.read_text())
        for key, bad in values.items():
            for recompute in (False, True):
                obj = dict(original)
                obj[key] = bad
                if recompute:
                    del obj['sum']
                    obj['sum'] = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()
                path.write_text(json.dumps(obj))
                with pytest.raises(hub_approval.Refused) as exc:
                    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
                assert exc.value.code == 'state_lost'
        for operation in ('missing_sum', 'extra_key', 'missing_key', 'truncate'):
            obj = dict(original)
            if operation == 'missing_sum':
                del obj['sum']
            elif operation == 'extra_key':
                obj['extra'] = 1
            elif operation == 'missing_key':
                del obj[next(k for k in obj if k != 'sum')]
            if operation in ('extra_key', 'missing_key'):
                del obj['sum']
                obj['sum'] = hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()
            path.write_text('{' if operation == 'truncate' else json.dumps(obj))
            with pytest.raises(hub_approval.Refused) as exc:
                engine.deny(card['id'], card['nonce'], 'U0123ABCD')
            assert exc.value.code == 'state_lost'
        path.write_text(json.dumps(original))
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'

def test_refusal_approval_tracks_pending_before_record_step(setup):
    engine, state, clock = setup
    card = request(engine)
    with pytest.raises(hub_approval.Refused) as bad:
        engine.deny(card['id'], 'bad', 'U0123ABCD')
    assert (bad.value.code, bad.value.approval) == ('bad_input', 'kept')
    clock.write_text('1700000034')
    with pytest.raises(hub_approval.Refused) as backwards:
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert (backwards.value.code, backwards.value.approval) == ('clock_backwards', 'kept')
    clock.write_text('1700000040')
    serial = state / 'serial.json'
    saved = serial.read_bytes()
    serial.unlink()
    with pytest.raises(hub_approval.Refused) as lost:
        engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert (lost.value.code, lost.value.approval) == ('state_lost', 'kept')
    serial.write_bytes(saved)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')

def test_forged_key_cannot_spend_valid_code(setup):
    engine, state, clock = setup
    card = request(engine)
    now = 1700000070
    clock.write_text(str(now))
    code, at = hub_approval.totp_code(SECRET, now), str(now)
    forged = hub_approval.approval_mac(bytes(32), card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, forged)
    assert (exc.value.code, exc.value.approval) == ('signature', 'kept')
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    approve(engine, card, now, code=code)
    assert engine.show(card['id'])['state'] == 'approved'

@pytest.mark.parametrize('filename', ['serial.json', 'totp-state.json', 'clock-hw.json'])
@pytest.mark.parametrize('event', ['request', 'approve', 'deny', 'begin_promote', 'authorize_push', 'note_refusal', 'commit_moved', 'finish_unmoved'])
def test_state_loss_precedes_every_locked_call(setup, filename, event):
    engine, state, clock = setup
    card = request(engine)
    path = state / filename
    original = path.read_bytes()
    path.unlink()
    now = 1700000040
    code, at = hub_approval.totp_code(SECRET, now), str(now)
    sig = hub_approval.approval_mac(KEY, card['id'], card['nonce'], 'U0123ABCD', card['check'], code, at)
    attempt = {'tag': TAG, 'object': 'c'*40, 'old': 'b'*40}
    calls = {'request': lambda: request(engine), 'approve': lambda: engine.approve(card['id'], card['nonce'], 'U0123ABCD', code, card['check'], at, sig), 'deny': lambda: engine.deny(card['id'], card['nonce'], 'U0123ABCD'), 'begin_promote': lambda: engine.begin_promote(card['id'], SHA), 'authorize_push': lambda: engine.authorize_push(card['id'], SHA, attempt), 'note_refusal': lambda: engine.note_refusal(card['id'], 'not_green'), 'commit_moved': lambda: engine.commit_moved(card['id'], 'b'*40, SHA, TAG), 'finish_unmoved': lambda: engine.finish_unmoved(card['id'])}
    before = {p.name:p.read_bytes() for p in state.glob('*.json')}
    with pytest.raises(hub_approval.Refused) as exc:
        calls[event]()
    assert exc.value.code == 'state_lost'
    assert before == {p.name:p.read_bytes() for p in state.glob('*.json')}
    path.write_bytes(original)
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert engine.show(card['id'])['state'] == 'denied'

def test_approve_early_refusals_do_not_read_records(setup, monkeypatch):
    engine, state, clock = setup
    card = request(engine)
    missing = 'p999-01234567'
    before = {p.name:p.read_bytes() for p in state.iterdir()}
    real_read = engine._read
    def guarded(name, kind):
        assert kind != 'record', 'early approve read a record'
        return real_read(name, kind)
    monkeypatch.setattr(engine, '_read', guarded)
    replies = []
    for id in (card['id'], missing):
        with pytest.raises(hub_approval.Refused) as exc:
            engine.approve(id, 'bad', 'U0123ABCD', '123456', '03Q1', '1700000040', '')
        replies.append(hub_approval.to_wire(exc.value))
        assert (exc.value.code, exc.value.approval) == ('bad_input', 'kept')
    assert replies[0] == replies[1]
    assert before == {p.name:p.read_bytes() for p in state.iterdir()}
    with pytest.raises(hub_approval.Refused) as malformed:
        engine.approve('bad/id', 'bad', 'U0123ABCD', '123456', '03Q1', '1700000040', '')
    assert (malformed.value.code, malformed.value.approval) == ('malformed_id', 'kept')
    serial = state / 'serial.json'
    original = serial.read_bytes()
    serial.unlink()
    with pytest.raises(hub_approval.Refused) as lost:
        engine.approve(card['id'], card['nonce'], 'U0123ABCD', '123456', card['check'], '1700000040', '')
    assert (lost.value.code, lost.value.approval) == ('state_lost', 'kept')
    serial.write_bytes(original)
    clock.write_text('1700000034')
    with pytest.raises(hub_approval.Refused) as backwards:
        engine.approve(card['id'], card['nonce'], 'U0123ABCD', '123456', card['check'], '1700000034', '')
    assert (backwards.value.code, backwards.value.approval) == ('clock_backwards', 'kept')
    assert all(json.loads(line)['sha7'] is None for line in (state / 'audit.jsonl').read_text().splitlines()[-2:])
    monkeypatch.setattr(engine, '_read', real_read)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    assert engine.show(card['id'])['state'] == 'approved'

@pytest.mark.parametrize('kind', ['bad_input', 'signature', 'envelope_stale'])
def test_empty_dir_early_refusal_listing(setup, kind):
    engine, state, clock = setup
    assert list(state.iterdir()) == []
    id, nonce, actor, code, check = 'p1-01234567', '0'*16, 'U0123ABCD', '123456', 'ABCD'
    at = '1699999000' if kind == 'envelope_stale' else '1700000040'
    sig = hub_approval.approval_mac(KEY, id, nonce, actor, check, code, at) if kind == 'envelope_stale' else ''
    if kind == 'bad_input':
        nonce = 'bad'
    with pytest.raises(hub_approval.Refused) as exc:
        engine.approve(id, nonce, actor, code, check, at, sig)
    assert (exc.value.code, exc.value.approval) == (kind, 'kept')
    assert {p.name for p in state.iterdir()} == (set() if kind == 'bad_input' else {'.lock', 'audit.jsonl'})
    assert request(engine)['id'].startswith('p1-')

def test_exit_map_and_wire_failures(setup, monkeypatch):
    engine, state, clock = setup
    rows = [({}, 'ok', 0), (hub_approval.Refused('not_pending', approval='final'), 'not_pending', 1), (hub_approval.Refused('bad_input', approval='kept'), 'bad_input', 2), (hub_approval.Refused('signature', approval='kept'), 'signature', 1), (hub_approval.Refused('envelope_stale', approval='kept'), 'envelope_stale', 1), (hub_approval.Unknown('busy'), 'busy', 75)]
    for value, code, exit_status in rows:
        wire = json.loads(hub_approval.to_wire(value))
        assert wire['code'] == code and hub_approval.exit_code(wire) == exit_status
        if isinstance(value, hub_approval.Refused):
            assert wire['data'] == {'approval': value.approval}
    disabled = hub_approval.Engine(state, engine.clock, None, engine.operators, KEY)
    with pytest.raises(hub_approval.Unknown) as unconfigured:
        request(disabled)
    wire = json.loads(hub_approval.to_wire(unconfigured.value))
    assert wire['code'] == 'unconfigured' and wire['data'] == {} and hub_approval.exit_code(wire) == 75
    real_replace = engine._replace
    def fail_replace(name, value):
        raise OSError('injected')
    monkeypatch.setattr(engine, '_replace', fail_replace)
    with pytest.raises(hub_approval.Unknown) as io:
        request(engine)
    wire = json.loads(hub_approval.to_wire(io.value))
    assert wire['code'] == 'io' and wire['data'] == {} and hub_approval.exit_code(wire) == 75
    monkeypatch.setattr(engine, '_replace', real_replace)
    assert request(engine)['id'].startswith('p1-')

def test_show_field_set_and_replace_order(setup, monkeypatch):
    engine, state, clock = setup
    card = request(engine)
    assert set(engine.show(card['id'])) == {'id','state','sha','branch','channel','requested_by','created','expires','check','approver','approved_at','reason','refusals','push_at','old','new','tag'}
    clock.write_text('1700000070')
    seen = []
    original = engine._replace
    def record_replace(name, value):
        seen.append(name)
        return original(name, value)
    monkeypatch.setattr(engine, '_replace', record_replace)
    approve(engine, card, 1700000070)
    assert seen == ['clock-hw.json', 'totp-state.json', card['id'] + '.json']
    assert engine.show(card['id'])['state'] == 'approved'

def test_audit_one_line_per_locked_call_and_none_before_lock(setup):
    engine, state, clock = setup
    card = request(engine)
    audit = state / 'audit.jsonl'
    def count():
        return len(audit.read_text().splitlines())
    assert count() == 1
    engine.show(card['id'])
    assert count() == 1
    disabled = hub_approval.Engine(state, engine.clock, None, engine.operators, KEY)
    with pytest.raises(hub_approval.Unknown):
        request(disabled)
    with pytest.raises(hub_approval.Refused):
        engine.deny('bad/id', 'bad', 'bad')
    with pytest.raises(hub_approval.Refused):
        engine.deny(card['id'], 'bad', 'U0123ABCD')
    state.chmod(0o755)
    try:
        with pytest.raises(hub_approval.Unknown):
            request(engine)
    finally:
        state.chmod(0o700)
    assert count() == 1
    with pytest.raises(hub_approval.Refused):
        engine.deny(card['id'], '0'*16 if card['nonce'] != '0'*16 else '1'*16, 'U0123ABCD')
    assert count() == 2
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')
    assert count() == 3

@pytest.mark.parametrize('secret,key', [(None, KEY), (SECRET, None)])
def test_unconfigured_request_and_approve_write_nothing(setup, secret, key):
    engine, state, clock = setup
    card = request(engine)
    disabled = hub_approval.Engine(state, engine.clock, secret, engine.operators, key)
    before = {p.name:p.read_bytes() for p in state.iterdir()}
    for call in (lambda: request(disabled), lambda: disabled.approve(card['id'], card['nonce'], 'U0123ABCD', '123456', card['check'], '1700000040', '')):
        with pytest.raises(hub_approval.Unknown) as exc:
            call()
        assert exc.value.code == 'unconfigured'
    assert before == {p.name:p.read_bytes() for p in state.iterdir()}
    engine.deny(card['id'], card['nonce'], 'U0123ABCD')

def test_consumed_new_mismatch_and_engine_refusal_code(setup):
    engine, state, clock = setup
    card = request(engine)
    clock.write_text('1700000070')
    approve(engine, card, 1700000070)
    with pytest.raises(hub_approval.Refused) as bad:
        engine.note_refusal(card['id'], 'not_found')
    assert bad.value.code == 'bad_input'
    engine.authorize_push(card['id'], SHA, {'tag':TAG, 'object':'c'*40, 'old':'b'*40})
    engine.commit_moved(card['id'], 'b'*40, SHA, TAG)
    with pytest.raises(hub_approval.Refused) as mismatch:
        engine.commit_moved(card['id'], 'b'*40, 'c'*40, TAG)
    assert mismatch.value.code == 'sha_mismatch'
    engine.commit_moved(card['id'], 'b'*40, SHA, TAG)

def test_approve_bad_input_same_reply_for_pending_final_missing(setup):
    engine, state, clock = setup
    final_card = request(engine)
    engine.deny(final_card['id'], final_card['nonce'], 'U0123ABCD')
    pending = request(engine)
    before = {p.name:p.read_bytes() for p in state.iterdir()}
    replies = []
    for id in (pending['id'], final_card['id'], 'p999-01234567'):
        with pytest.raises(hub_approval.Refused) as exc:
            engine.approve(id, 'bad', 'U0123ABCD', '123456', '03Q1', '1700000040', '')
        replies.append(hub_approval.to_wire(exc.value))
    assert replies[0] == replies[1] == replies[2]
    assert json.loads(replies[0])['data'] == {'approval': 'kept'}
    assert before == {p.name:p.read_bytes() for p in state.iterdir()}
    clock.write_text('1700000070')
    approve(engine, pending, 1700000070)
    assert engine.show(pending['id'])['state'] == 'approved'
