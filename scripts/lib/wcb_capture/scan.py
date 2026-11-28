"""Independent privacy scan for filtered evidence."""
import ipaddress
import getpass
import os
import re
from collections import namedtuple

from . import isolation


Hit = namedtuple('Hit', 'pattern line')
_PATTERNS = [
    ('bearer', re.compile(r'(?i)bearer')),
    ('jwt', re.compile(r'eyJ[A-Za-z0-9_-]{10,}')),
    ('private_key', re.compile(r'BEGIN ')),
    ('key_body', re.compile(r'(?i)(?:ssh-(?:rsa|ed25519)|ecdsa-sha2-nistp\d+)\s+AAAA[A-Za-z0-9+/]{16,}')),
    ('email', re.compile(r'@[a-z0-9.-]+\.[a-z]{2,}', re.I)),
    ('ipv4', re.compile(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])')),
    ('ipv6', re.compile(r'(?<![\w:])(?:[0-9a-f]*:){2,}[0-9a-f:]*[0-9a-f](?![\w:])', re.I)),
    ('local_domain', re.compile(r'\.local\b', re.I)),
]


def _lines(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as stream:
        return stream.readlines()


def scan_file(path, terms_path=None, login=None, home=None):
    """Return pattern names and line numbers only; never return matched text."""
    try:
        operator, _ = isolation.scratch_dirs()
        terms_path = terms_path or operator / 'terms'
    except isolation.Refused:
        terms_path = terms_path or None
    terms = []
    if terms_path and os.path.isfile(terms_path):
        with open(terms_path, 'r', encoding='utf-8', errors='replace') as stream:
            terms = [line.strip() for line in stream if line.strip()]
    if login:
        terms.append(login)
        if len(login) > 16:
            terms.append(login[:16])
    if home:
        terms.append(home)
    else:
        terms.append(os.path.expanduser('~'))
    if login:
        terms.append(login)
    else:
        try:
            terms.append(getpass.getuser())
            if len(terms[-1]) > 16:
                terms.append(terms[-1][:16])
        except Exception:
            pass
    hits = []
    for number, line in enumerate(_lines(path), 1):
        for name, pattern in _PATTERNS:
            for match in pattern.finditer(line):
                value = match.group(0)
                if name == 'email' and value.lower() in ('@openssh.com', '@libssh.org'):
                    continue
                if name == 'ipv4':
                    try:
                        if ipaddress.ip_address(value) in (ipaddress.ip_address('127.0.0.1'), ipaddress.ip_address('0.0.0.0')):
                            continue
                    except ValueError:
                        pass
                if name == 'ipv6':
                    try:
                        address = ipaddress.ip_address(value)
                        if address == ipaddress.ip_address('::1'):
                            continue
                    except ValueError:
                        # A clock such as HH:MM:SS is not an IP literal.
                        continue
                hits.append(Hit(name, number))
        for term in terms:
            if term and term in line:
                hits.append(Hit('term', number))
    return hits
