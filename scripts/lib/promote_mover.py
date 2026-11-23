"""Policy evaluator and remote mover for approved hub promotions."""
import json
import os
import re
import subprocess
import time

import hub_approval

GIT = "/Library/Developer/CommandLineTools/usr/bin/git"
ID = re.compile(r"p[0-9]+-[0-9a-f]{8}\Z")
SHA = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
BRANCH = re.compile(r"k3d-manager-v([0-9]+)\.([0-9]+)\.([0-9]+)\Z")


class CurlApi:
    def __init__(self, token_path):
        self.token_path = token_path

    def get(self, path, timeout):
        try:
            with open(self.token_path, encoding="utf-8") as stream:
                token = stream.read().strip()
            config = 'url = "https://api.github.com{}"\nheader = "Authorization: Bearer {}"\nheader = "Accept: application/vnd.github+json"\n'.format(path, token)
            result = subprocess.run(
                ["/usr/bin/curl", "-q", "-sS", "--max-time", str(timeout), "-w", "\n%{http_code}", "-K", "-"],
                input=config, text=True, capture_output=True, timeout=timeout + 1,
                env={"PATH": "/usr/bin:/bin"}, check=False,
            )
            if result.returncode:
                return 0, None
            body, sep, status = result.stdout.rpartition("\n")
            if not sep or not status.isdigit():
                return 0, None
            code = int(status)
            if not 200 <= code < 300:
                return code, None
            return code, json.loads(body)
        except (OSError, subprocess.SubprocessError, ValueError, TypeError):
            return 0, None

    def get_all(self, path, list_key, budget):
        items = []
        total = None
        for page in range(1, 12):
            if page > 10:
                return 0, []
            timeout = budget()
            sep = "&" if "?" in path else "?"
            status, body = self.get("{}{}per_page=100&page={}".format(path, sep, page), timeout)
            if not 200 <= status < 300:
                return status or 0, []
            if list_key is None:
                if not isinstance(body, list):
                    return 0, []
                current = body
            else:
                if not isinstance(body, dict) or not isinstance(body.get(list_key), list):
                    return 0, []
                current = body[list_key]
                if type(body.get("total_count")) is int:
                    total = body["total_count"]
            items.extend(current)
            if (total is not None and len(items) >= total) or len(current) < 100:
                return status, items
        return 0, []


class Mover:
    def __init__(self, repo_url, repo_slug, api, ssh_command, workdir, clock, monotonic=time.monotonic, git=GIT):
        self.repo_url = repo_url
        self.repo_slug = repo_slug
        self.api = api
        self.ssh_command = ssh_command
        self.workdir = workdir
        self.clock = clock
        self.monotonic = monotonic
        self.git = git

    def _timeout(self, deadline, default):
        remaining = deadline - self.monotonic()
        if remaining < 1:
            raise hub_approval.Unknown("deadline")
        return min(default, remaining)

    def _run(self, args, deadline=None, default=60, input_text=None, check=True):
        timeout = default if deadline is None else self._timeout(deadline, default)
        env = {"PATH": "/usr/bin:/bin", "HOME": self.workdir,
               "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
               "GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": self.ssh_command}
        try:
            result = subprocess.run([self.git, "-c", "core.hooksPath=/dev/null"] + args,
                                    cwd=self.workdir, env=env, input=input_text, text=True,
                                    capture_output=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            if check:
                raise hub_approval.Unknown("lookup_failed", str(exc))
            return None
        if check and result.returncode:
            raise hub_approval.Unknown("lookup_failed", result.stderr.strip())
        return result

    def _init(self, deadline=None, default=60):
        if not os.path.exists(os.path.join(self.workdir, "HEAD")):
            timeout = default if deadline is None else self._timeout(deadline, default)
            os.makedirs(os.path.dirname(self.workdir), exist_ok=True)
            try:
                result = subprocess.run([self.git, "-c", "core.hooksPath=/dev/null", "init", "--bare", "-q", self.workdir],
                                        env={"PATH": "/usr/bin:/bin", "HOME": self.workdir,
                                             "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                                             "GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": self.ssh_command},
                                        capture_output=True, text=True, timeout=timeout, check=False)
            except (OSError, subprocess.SubprocessError) as exc:
                raise hub_approval.Unknown("lookup_failed", str(exc))
            if result.returncode:
                raise hub_approval.Unknown("lookup_failed", result.stderr.strip())

    def _git(self, args, deadline=None, default=60, input_text=None, check=True):
        self._init(deadline, default)
        return self._run(args, deadline, default, input_text, check)

    def _fetch(self, deadline=None):
        self._git(["fetch", "-q", "--prune", "--no-tags", self.repo_url,
                   "+refs/heads/*:refs/k3dm/remote/heads/*",
                   "+refs/tags/hub-promote/*:refs/k3dm/witness/*"], deadline)

    def prime(self):
        self._init(default=600)
        self._git(["fetch", "-q", "--prune", "--no-tags", self.repo_url,
                   "+refs/heads/*:refs/k3dm/remote/heads/*",
                   "+refs/tags/hub-promote/*:refs/k3dm/witness/*"], default=600)

    def _ls_remote(self, refs, deadline=None, default=60):
        result = self._git(["ls-remote", self.repo_url] + list(refs), deadline, default)
        found = {}
        for line in result.stdout.splitlines():
            fields = line.split("\t", 1)
            if len(fields) == 2 and not fields[1].endswith("^{}") and fields[1] in refs:
                found[fields[1]] = fields[0]
        return found

    def _branches(self):
        result = self._git(["for-each-ref", "--format=%(refname) %(objectname)", "refs/k3dm/remote/heads"])
        candidates = []
        tips = {}
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) != 2:
                continue
            name = fields[0].removeprefix("refs/k3dm/remote/heads/")
            match = BRANCH.fullmatch(name)
            if not match or any(part.startswith("0") and len(part) > 1 for part in match.groups()):
                continue
            version = tuple(int(part) for part in match.groups())
            candidates.append((version, name))
            tips[name] = fields[1]
        if not candidates:
            raise hub_approval.Refused("not_newest_branch", "no release branch found", "kept")
        return max(candidates)[1], tips

    def _deadline_api(self, deadline):
        return lambda: self._timeout(deadline, 20)

    def _api_all(self, path, key, deadline):
        status, items = self.api.get_all(path, key, self._deadline_api(deadline))
        if not 200 <= status < 300:
            raise hub_approval.Unknown("lookup_failed")
        return items

    def _check(self, commit, deadline):
        runs = self._api_all("/repos/{}/commits/{}/check-runs".format(self.repo_slug, commit), "check_runs", deadline)
        if not runs:
            return "none"
        if any(not isinstance(run, dict) or not isinstance(run.get("status"), str) for run in runs):
            raise hub_approval.Unknown("lookup_failed", "malformed check-runs response")
        if any(run.get("status") != "completed" for run in runs):
            return "pending"
        if any(run.get("conclusion") not in ("success", "neutral", "skipped") for run in runs):
            return "failed"
        return "green"

    def _witnesses(self, id, deadline=None):
        result = self._git(["for-each-ref", "--format=%(refname) %(objectname)", "refs/k3dm/witness"], deadline)
        matched = []
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) != 2:
                continue
            typ = self._git(["cat-file", "-t", fields[1]], deadline, check=False)
            if typ is None:
                raise hub_approval.Unknown("lookup_failed")
            if typ.returncode:
                raise hub_approval.Unknown("lookup_failed", typ.stderr.strip())
            if typ.stdout.strip() != "tag":
                continue
            data = self._git(["cat-file", "tag", fields[1]], deadline).stdout
            header, _, message = data.partition("\n\n")
            if "approval: {}".format(id) in message.splitlines():
                object_match = re.search(r"^object ([0-9a-f]{40,64})$", header, re.M)
                type_match = re.search(r"^type (\S+)$", header, re.M)
                tagger = re.search(r"^tagger ([^\n]+)$", header, re.M)
                matched.append({"ref": fields[0], "oid": fields[1], "object": object_match.group(1) if object_match else None,
                                "type": type_match.group(1) if type_match else None,
                                "tagger": tagger.group(1).split(" <", 1)[0] if tagger else None,
                                "message": message.rstrip("\n")})
        if len(matched) > 1:
            raise hub_approval.Refused("witness_conflict", "multiple witness tags name this approval", "kept")
        return matched

    def _block_witness(self, id, deadline):
        matches = self._witnesses(id, deadline)
        if matches:
            raise hub_approval.Refused("already_spent", "a hub-promote tag already names this approval; it can never move again", "kept")

    def _ancestor(self, first, second, deadline):
        result = self._git(["merge-base", "--is-ancestor", first, second], deadline, check=False)
        if result is None:
            raise hub_approval.Unknown("lookup_failed")
        if result.returncode == 0:
            return True
        if result.returncode == 1:
            return False
        raise hub_approval.Unknown("lookup_failed")

    def _contains(self, sha, old, deadline):
        cherry = self._git(["cherry", sha, old], deadline).stdout
        candidates = [line[2:].strip() for line in cherry.splitlines() if line.startswith("+ ")]
        if not candidates:
            return
        rows = self._api_all("/repos/{}/commits/{}/pulls".format(self.repo_slug, old), None, deadline)
        unresolved = False
        for row in rows:
            if not isinstance(row, dict) or row.get("merged_at") is None:
                continue
            head = row.get("head") if isinstance(row.get("head"), dict) else {}
            number, hsha, merge = row.get("number"), head.get("sha"), row.get("merge_commit_sha")
            if not (str(number).isdigit() and isinstance(hsha, str) and SHA.fullmatch(hsha) and isinstance(merge, str) and SHA.fullmatch(merge)):
                continue
            ref = "refs/pull/{}/head".format(number)
            try:
                remote = self._ls_remote([ref], deadline).get(ref)
            except hub_approval.Unknown:
                unresolved = True
                continue
            if remote is None:
                unresolved = True
                continue
            if remote != hsha:
                continue
            exists = self._git(["cat-file", "-e", hsha], deadline, check=False)
            if exists is None:
                unresolved = True
                continue
            if exists.returncode:
                fetched = self._git(["fetch", "-q", "--no-tags", self.repo_url, ref], deadline, check=False)
                if fetched is None or fetched.returncode:
                    unresolved = True
                    continue
            merge_exists = self._git(["cat-file", "-e", merge], deadline, check=False)
            if merge_exists is None:
                unresolved = True
                continue
            if merge_exists.returncode:
                continue
            if self._ancestor(old, hsha, deadline) and self._ancestor(merge, sha, deadline):
                return
        if unresolved:
            raise hub_approval.Unknown("lookup_failed")
        short = ", ".join(item[:7] for item in candidates[:5])
        raise hub_approval.Refused("not_contained", "uncontained commits: {}".format(short), "kept")

    def _green_walk(self, branch, deadline):
        result = self._git(["rev-list", "--first-parent", "-n", "20", "refs/k3dm/remote/heads/{}".format(branch)], deadline)
        commits = result.stdout.splitlines()
        states = []
        green = None
        for commit in commits:
            state = self._check(commit, deadline)
            states.append((commit, state))
            if state == "green":
                green = commit
                break
        return commits, states, green

    def _stamp(self):
        return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(self.clock.now()))

    def move(self, id, sha, branch, authorize, deadline):
        if not isinstance(id, str) or not ID.fullmatch(id) or not isinstance(sha, str) or not SHA.fullmatch(sha) or not isinstance(branch, str) or not BRANCH.fullmatch(branch):
            raise hub_approval.Refused("bad_input", "invalid promotion input", "kept")
        self._fetch(deadline)
        self._block_witness(id, deadline)
        oldref = "refs/heads/deploy/hub"
        old = self._ls_remote([oldref], deadline).get(oldref)
        if old is None:
            raise hub_approval.Refused("deploy_moved", "deploy/hub does not exist; the first promote is the manual bootstrap in docs/howto/hub-promote.md", "kept")
        if old == sha:
            raise hub_approval.Refused("deploy_moved", "deploy/hub is at that commit but not by this approval", "kept")
        newest, tips = self._branches()
        if branch != newest:
            raise hub_approval.Refused("not_newest_branch", "{} is not the newest release branch".format(branch), "kept")
        tip = tips[branch]
        self._contains(sha, old, deadline)
        commits, states, green = self._green_walk(branch, deadline)
        if green is None:
            raise hub_approval.Refused("not_green", "no green commit in the first 20 commits", "kept")
        if green != sha:
            raise hub_approval.Refused("not_newest_green", "newest green commit is {}".format(green), "kept")
        prefix = commits[:commits.index(sha) + 1]
        stamp = self._stamp()
        tag = "hub-promote/{}".format(stamp)
        tagref = "refs/tags/{}".format(tag)
        if self._ls_remote([tagref], deadline).get(tagref):
            raise hub_approval.Refused("tag_exists", "promotion tag already exists", "kept")
        tagger_time = self.clock.now()
        message = "action: promote\nold: {}\nnew: {}\nREF: {}\napproval: {}".format(old, sha, sha, id)
        tagdata = "object {}\ntype commit\ntag {}\ntagger k3dm-promote <k3dm-promote@localhost> {} +0000\n\n{}\n".format(sha, tag, tagger_time, message)
        obj = self._git(["mktag"], deadline, input_text=tagdata).stdout.strip()
        self._git(["update-ref", "refs/k3dm/pending/{}".format(stamp), obj], deadline)

        self._fetch(deadline)
        self._block_witness(id, deadline)
        current_newest, current_tips = self._branches()
        if current_newest != branch or current_tips.get(branch) != tip:
            raise hub_approval.Refused("release_moved", "release branch moved during evaluation", "kept")
        for commit in prefix:
            state = self._check(commit, deadline)
            if (commit == sha and state != "green") or (commit != sha and state == "green"):
                raise hub_approval.Refused("release_moved", "newest green changed during evaluation", "kept")
        if self._ls_remote([oldref], deadline).get(oldref) != old:
            raise hub_approval.Refused("deploy_moved", "deploy/hub moved during evaluation", "kept")
        self._timeout(deadline, 60)
        authorize({"tag": tag, "object": obj, "old": old})

        push = self._git(["push", "--porcelain", "--force-with-lease={}:{}".format(oldref, old), self.repo_url,
                          "{}:{}".format(sha, oldref)], default=60, check=False)
        lines = [] if push is None else [line for line in push.stdout.splitlines() if "\t" in line and not line.startswith(("remote:", "error:"))]
        parsed = []
        for line in lines:
            fields = line.split("\t")
            if len(fields) == 3 and ":" in fields[1]:
                parsed.append((fields[0], fields[1].rsplit(":", 1)[1]))
        matching = [flag for flag, target in parsed if target == oldref]
        if push is not None and push.returncode == 0 and len(matching) == 1 and matching[0] in (" ", "+"):
            self._git(["update-ref", "refs/k3dm/moved/{}".format(stamp), obj], default=60, check=False)
            self._git(["push", "--porcelain", self.repo_url, "{}:{}".format(obj, tagref)], default=60, check=False)
            observed = self._git(["ls-remote", self.repo_url, tagref], default=30, check=False)
            if observed is None or observed.returncode:
                raise hub_approval.Unknown("push_unknown", "deploy/hub moved; witness tag observation failed")
            actual = self._parse_one(observed.stdout, tagref)
            if actual == obj:
                return {"outcome": "moved", "old": old, "new": sha, "tag": tag}
            if actual:
                raise hub_approval.Refused("witness_conflict", "deploy/hub was moved to {} by this approval but its witness tag name is taken".format(sha[:7]), "kept")
            raise hub_approval.Unknown("push_unknown", "deploy/hub moved; the witness tag is not yet on the remote; rerun with the same approval")
        if matching == ["="] and push is not None and push.returncode == 0:
            raise hub_approval.Refused("deploy_moved", "deploy/hub was already at that commit, moved by another writer, not by this approval; no tag written", "kept")
        observed = self._git(["ls-remote", self.repo_url, oldref], default=30, check=False)
        if observed is None or observed.returncode:
            raise hub_approval.Unknown("push_unknown")
        actual = self._parse_one(observed.stdout, oldref)
        if actual == old:
            raise hub_approval.Unknown("push_unknown")
        if actual == sha:
            raise hub_approval.Refused("deploy_moved", "deploy/hub is at that commit but this approval's push was not confirmed; no tag written", "kept")
        raise hub_approval.Refused("deploy_moved", "deploy/hub moved during push", "kept")

    @staticmethod
    def _parse_one(output, ref):
        for line in output.splitlines():
            fields = line.split("\t", 1)
            if len(fields) == 2 and fields[1] == ref and not fields[1].endswith("^{}"):
                return fields[0]
        return None

    def witness(self, id, sha, branch, attempt, deadline):
        if not isinstance(id, str) or not ID.fullmatch(id) or not isinstance(sha, str) or not SHA.fullmatch(sha) or not isinstance(branch, str) or not BRANCH.fullmatch(branch):
            raise hub_approval.Refused("bad_input", "invalid promotion input", "kept")
        self._fetch(deadline)
        tag = attempt["tag"]
        stamp = tag.removeprefix("hub-promote/")
        obj = attempt["object"]
        marker = "refs/k3dm/moved/{}".format(stamp)
        marker_result = self._git(["rev-parse", "--verify", marker], deadline, check=False)
        marked = marker_result is not None and marker_result.returncode == 0 and marker_result.stdout.strip() == obj
        tagref = "refs/tags/{}".format(tag)
        remote = self._ls_remote([tagref], deadline).get(tagref)
        if marked and remote == obj:
            return {"outcome": "moved", "old": attempt["old"], "new": sha, "tag": tag}
        if marked and remote is None:
            self._git(["push", "--porcelain", self.repo_url, "{}:{}".format(obj, tagref)], default=60, check=False)
            result = self._git(["ls-remote", self.repo_url, tagref], default=30, check=False)
            if result is None or result.returncode:
                raise hub_approval.Unknown("push_unknown")
            value = self._parse_one(result.stdout, tagref)
            if value == obj:
                return {"outcome": "moved", "old": attempt["old"], "new": sha, "tag": tag}
            if value:
                raise hub_approval.Refused("witness_conflict", "witness tag name is taken", "kept")
            raise hub_approval.Unknown("push_unknown")
        if marked and remote:
            raise hub_approval.Refused("witness_conflict", "witness tag name is taken", "kept")
        if remote == obj:
            raise hub_approval.Refused("witness_conflict", "remote witness has no local move marker", "kept")
        matches = self._witnesses(id, deadline)
        if matches:
            raise hub_approval.Refused("already_spent", "a hub-promote tag already names this approval", "kept")
        return None

    def drop_pending(self, tag):
        stamp = tag.removeprefix("hub-promote/")
        for ref in ("refs/k3dm/pending/{}".format(stamp), "refs/k3dm/moved/{}".format(stamp)):
            self._git(["update-ref", "-d", ref], check=False)


def promote(engine, mover, id, sha, deadline):
    result = engine.begin_promote(id, sha)
    mode = result["mode"]
    record = result["record"]
    if mode == "consumed":
        return {"outcome": "already", "old": record["old"], "new": record["new"], "tag": record["tag"]}

    def commit(value):
        try:
            engine.commit_moved(id, value["old"], value["new"], value["tag"])
        except Exception as exc:
            raise hub_approval.Unknown("push_unknown", "move recorded by {}; engine commit failed: {}".format(value["tag"], exc))
        mover.drop_pending(value["tag"])
        return value

    if mode == "recover":
        try:
            witnessed = mover.witness(id, sha, record["branch"], record["attempt"], deadline)
        except hub_approval.Refused as exc:
            raise hub_approval.Refused(exc.code, exc.message, "final")
        if witnessed:
            return commit(witnessed)
        finished = engine.finish_unmoved(id)
        if finished.get("state") == "expired":
            raise hub_approval.Refused("expired", approval="final")
    try:
        authorization_error = [None]
        def authorize(attempt):
            try:
                return engine.authorize_push(id, sha, attempt)
            except (hub_approval.Refused, hub_approval.Unknown) as exc:
                authorization_error[0] = exc
                raise
        value = mover.move(id, sha, record["branch"],
                           authorize, deadline)
    except hub_approval.Refused as exc:
        if authorization_error[0] is exc:
            raise
        if exc.code in ("already_spent", "witness_conflict"):
            raise hub_approval.Refused(exc.code, exc.message, "final")
        if exc.code == "bad_input":
            raise
        try:
            engine.note_refusal(id, exc.code)
        except hub_approval.Refused as note_error:
            raise hub_approval.Refused(exc.code, exc.message, note_error.approval)
        raise hub_approval.Refused(exc.code, exc.message, "kept")
    return commit(value)
