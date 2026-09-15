from hermes.e2e_triage import classify, diff_groups, group_slug, redact, triage


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
