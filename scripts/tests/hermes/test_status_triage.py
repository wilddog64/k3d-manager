import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.e2e_triage import diff_groups
from hermes.status_triage import classify, triage


def check(check_id, message="failed"):
    return {"id": check_id, "message": message, "status": "error"}


def test_classify_uses_the_status_id_policy_in_order():
    assert classify(check("status_source"))[0] == "status-source"
    assert classify(check("frontend_sso_login"))[0] == "sso-auth"
    assert classify(check("keycloak_admin_login"))[0] == "sso-auth"
    assert classify(check("frontend", "HTTP 530"))[0] == "edge"
    assert classify(check("grafana_login"))[0] == "credential"
    assert classify(check("eso_store"))[0] == "sync"
    assert classify(check("argocd_sync"))[0] == "sync"
    assert classify(check("data_layer"))[0] == "data"
    assert classify(check("payment"))[0] == "service"


def test_triage_omits_status_source_and_redacts_every_group_string():
    groups = triage([check("status_source"), check("frontend_sso_login", "Bearer abc password=hunter2")])
    assert len(groups) == 1
    assert groups[0]["kind"] == "sso-auth"
    assert groups[0]["check_ids"] == ["frontend_sso_login"]
    assert "abc" not in json.dumps(groups)
    assert "hunter2" not in json.dumps(groups)


def test_diff_groups_identifies_new_ongoing_and_resolved_status_groups():
    previous = [{"slug": "e2e-sso-auth-frontend-sso-login"}, {"slug": "e2e-service-cart"}]
    current = [{"slug": "e2e-sso-auth-frontend-sso-login"}, {"slug": "e2e-service-payment"}]
    assert diff_groups(previous, current) == {"new": ["e2e-service-payment"],
                                               "ongoing": ["e2e-sso-auth-frontend-sso-login"],
                                               "resolved": ["e2e-service-cart"]}
