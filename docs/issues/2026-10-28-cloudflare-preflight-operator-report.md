# Cloudflare preflight operator report and Make shortcut

## Result: partial preflight, no change approval

Operator ran the explicit read-only helper. All seven hosts negotiate TLS1.2
and1.3 with certificate validation. Legacy TLS probes report client_unsupported;
this is not evidence the edge rejects TLS1.0/1.1. No HTTP root response upgrades
to HTTPS. ArgoCD/frontend return200, authenticated endpoints401, Grafana/Keycloak
302 point to same-scheme paths. No credentials were sent in these public probes.

API values allnull, source_error credential or valid zone id unavailable.
The provided zone ID passes the helper's32hex validation, so the helper's
existing branch indicates a missing/empty CLOUDFLARE_API_TOKEN in that shell.
No token value was requested or recorded. Current settings, redirect rules,
certificate coverage and authenticated SSO/Slack compatibility remain pending.
F0 is not complete and no F1 live settings change is approved here.

The four deprecation warnings are from intentionally setting old TLS protocol
bounds. Record them without interpreting them as handshake rejection; no
warning suppression or TLS policy changes added to satisfy this Make request.

## Operator command and complete reported output

The following warnings and JSON are transcribed from the operator's message;
this is operator evidence, not a new coordinator probe.

```text
bin/k3dm-cloudflare-posture --check --zone-id faf14ba309c1626ef195ae31bd730dd1
/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-cloudflare-posture:246: DeprecationWarning: ssl.TLSVersion.TLSv1 is deprecated
  context.minimum_version = selected
/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-cloudflare-posture:247: DeprecationWarning: ssl.TLSVersion.TLSv1 is deprecated
  context.maximum_version = selected
/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-cloudflare-posture:246: DeprecationWarning: ssl.TLSVersion.TLSv1_1 is deprecated
  context.minimum_version = selected
/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-cloudflare-posture:247: DeprecationWarning: ssl.TLSVersion.TLSv1_1 is deprecated
  context.maximum_version = selected
{
  "exit_status_meaning": "report completion only; F0 requires operator review",
  "f0_complete": false,
  "posture": {
    "https_enforcement": "unknown",
    "minimum_tls": "unknown"
  },
  "probes": {
    "alertmanager.3ai-talk.org": {
      "http": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 401
      },
      "https": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 401
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    },
    "argocd.3ai-talk.org": {
      "http": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 200
      },
      "https": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 200
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    },
    "frontend.3ai-talk.org": {
      "http": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 200
      },
      "https": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 200
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    },
    "grafana.3ai-talk.org": {
      "http": {
        "location": "http://grafana.3ai-talk.org/[redacted]",
        "redirect": {
          "destination_host_known": true,
          "https_equivalent": false,
          "self_redirect": false,
          "transport": "same_scheme"
        },
        "result": "response",
        "status": 302
      },
      "https": {
        "location": "https://grafana.3ai-talk.org/[redacted]",
        "redirect": {
          "destination_host_known": true,
          "https_equivalent": false,
          "self_redirect": false,
          "transport": "same_scheme"
        },
        "result": "response",
        "status": 302
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    },
    "keycloak.3ai-talk.org": {
      "http": {
        "location": "http://keycloak.3ai-talk.org/[redacted]",
        "redirect": {
          "destination_host_known": true,
          "https_equivalent": false,
          "self_redirect": false,
          "transport": "same_scheme"
        },
        "result": "response",
        "status": 302
      },
      "https": {
        "location": "https://keycloak.3ai-talk.org/[redacted]",
        "redirect": {
          "destination_host_known": true,
          "https_equivalent": false,
          "self_redirect": false,
          "transport": "same_scheme"
        },
        "result": "response",
        "status": 302
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    },
    "prometheus.3ai-talk.org": {
      "http": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 401
      },
      "https": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 401
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    },
    "webhook.3ai-talk.org": {
      "http": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 401
      },
      "https": {
        "location": null,
        "redirect": null,
        "result": "response",
        "status": 401
      },
      "tls": {
        "1.0": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.1": {
          "certificate_valid": null,
          "negotiated": null,
          "result": "client_unsupported"
        },
        "1.2": {
          "certificate_valid": true,
          "negotiated": "TLSv1.2",
          "result": "negotiated"
        },
        "1.3": {
          "certificate_valid": true,
          "negotiated": "TLSv1.3",
          "result": "negotiated"
        }
      }
    }
  },
  "settings": {
    "always_use_https": null,
    "min_tls_version": null,
    "security_header": null,
    "ssl": null,
    "tls_1_3": null
  },
  "source": "Cloudflare API",
  "source_error": "credential or valid zone id unavailable",
  "timestamp_utc": "2026-10-28T17:36:46.131214+00:00"
}
```

## Explicitly requested implementation

Add only Makefile cloudflare-preflight plus its help entry and existing howto
usage. ZONE_ID forwards to the existing helper; DRY_RUN=1 matches webhook-doctor
convention. No helper changes, API writes, credential retrieval, new secrets,
scheduler, UI changes or new tests mirroring the one-command wrapper.

Actual make -n cloudflare-preflight ZONE_ID=<operator zone> (exit0):

```text
bin/k3dm-cloudflare-posture --check --zone-id 'faf14ba309c1626ef195ae31bd730dd1'
```

Actual make cloudflare-preflight DRY_RUN=1 ZONE_ID=<operator zone> (exit0):

```text
Read-only plan: optionally read Cloudflare zone settings and probe the seven fixed public hosts; no access performed. Use --check explicitly.
```

Diff check exit0/no output. No actual --check executed by coordinator.
BATS/Python helper logic unchanged, so existing helper169-case proof remains
prior evidence rather than a claimed rerun. Required staged lint/audit/hooks
run before commit. Cloudflare security bug remains OPEN.
