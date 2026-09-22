from hermes.e2e_triage import classify, diff_groups, group_slug, redact, repo_for, service_for, triage


def failure(file, error, status="failed"):
    return {"file": file, "title": "works", "error": error, "status": status}


def test_rules_ports_and_regression_groups():
    failures = [
        failure("api/payment.spec.ts", "connect ECONNREFUSED 10.0.0.4:8084"),
        failure("api/cart.spec.ts", "Received: undefined"),
        failure("api/orders.spec.ts", "Cannot read properties of undefined"),
        failure("api/cross-service.spec.ts", "must have a length property"),
        failure("api/products.spec.ts", 'Expected: "number" Received: "string"'),
    ]
    groups = triage({"result": "fail"}, failures)
    assert {(item["kind"], item["target"]) for item in groups} == {
        ("service-unreachable", "payment"), ("contract-drift", "api-cart"),
        ("contract-drift", "api-orders"), ("contract-drift", "api-cross-service"),
        ("contract-drift", "api-products")}
    assert classify(failure("x.spec.ts", "ENOTFOUND localhost:8000"))[1] == "product-catalog"
    assert classify(failure("x.spec.ts", "Timeout 30000ms exceeded"))[0] == "timeout"
    assert classify(failure("x.spec.ts", "no match"))[0] == "assertion"


def test_pass_harness_slug_redaction_and_diff():
    assert triage({"result": "pass"}, []) == []
    assert triage({"result": "fail", "phase": "dispatch"}, [])[0]["target"] == "dispatch"
    assert group_slug("assertion", "../ Weird space") == "e2e-assertion-weird-space"
    value = redact("Bearer abc token=hide eyJaaa.bbb.ccc password=alsohide")
    assert "hide" not in value and "<redacted>" in value
    assert diff_groups([{"slug": "old"}, {"slug": "same"}], [{"slug": "same"}, {"slug": "new"}]) == {
        "new": ["new"], "ongoing": ["same"], "resolved": ["old"]}


def test_auth_and_narrowing_rules():
    assert classify(failure("x.spec.ts", "Received: 401"))[0] == "auth"
    assert classify(failure("x.spec.ts", "invalid_grant"))[0] == "auth"
    assert classify(failure("x.spec.ts", "expect(res.status).toBe(404) / Received: 500"))[0] == "assertion"
    assert classify(failure("x.spec.ts", "expect(res.status).toBe(500) / Received: 500"))[0] == "assertion"


def test_tier_two_ports_and_routing():
    assert classify(failure("x.spec.ts", "connect ECONNREFUSED 10.0.0.1:8081"))[1] == "order"
    assert classify(failure("x.spec.ts", "connect ECONNREFUSED 10.0.0.2:8082"))[1] == "product-catalog"
    assert repo_for("basket") == "wilddog64/shopping-cart-basket"
    assert repo_for("order") == "wilddog64/shopping-cart-order"
    assert repo_for("payment") == "wilddog64/shopping-cart-payment"
    assert repo_for("product-catalog") == "wilddog64/shopping-cart-product-catalog"
    assert repo_for("frontend") == "wilddog64/shopping-cart-frontend"
    assert repo_for("cross-service") == "wilddog64/shopping-cart-e2e-tests"
    assert repo_for("unknown") is None
    assert service_for("cross-service") == "cross-service"
