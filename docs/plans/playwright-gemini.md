# Plan: Playwright Agents + Gemini CLI Integration

## Objective
Integrate the new Playwright AI Agents (Planner, Generator, Healer) and the Playwright MCP (Model Context Protocol) server into the Gemini CLI workflow to automate the end-to-end testing lifecycle for the `k3d-manager` project.

## Relationship: High-Level Orchestration
The relationship between Gemini CLI and Playwright Agents is one of **Orchestration**. Gemini CLI acts as the technical lead, managing high-level goals and project context, while the Playwright Agents and tools perform specialized browser-level tasks.

| Role | Agent | Responsibility |
| :--- | :--- | :--- |
| **Manager** | Gemini CLI | Orchestrates the entire workflow, manages project state, and handles CI/CD integration. |
| **Architect** | Playwright Planner | Explores the application and generates structured Markdown test plans. |
| **Developer** | Playwright Generator | Converts Markdown plans into executable `.spec.ts` files using live browser verification. |
| **Doctor** | Playwright Healer | Automatically analyzes test failures, inspects snapshots, and patches broken selectors or logic. |

## Why Playwright MCP? (Real-time "Browsing Agent")
While simple "on-the-fly" script generation is powerful, the **Playwright MCP hookup** is the superior approach. It transforms Gemini CLI into a true "Browsing Agent" by providing real-time senses and interaction:

*   **Real-time Feedback:** Instead of waiting for a script to fail, Gemini can see the DOM and screenshots after every action (click, fill, navigate) and self-correct during the thought process.
*   **Adaptive Debugging:** Gemini can handle dynamic UI elements, unexpected popups, and slow loading states by interacting with the live session.
*   **Efficiency:** Reduces the "Write -> Run -> Fail" loop by allowing the agent to "heal" selectors and logic in a live, multi-turn conversation with the browser.

## Cross-Browser Support
Playwright provides reliable, high-performance automation across all modern rendering engines:
- **Chromium:** Google Chrome, Microsoft Edge.
- **Firefox:** Mozilla Gecko.
- **WebKit:** Apple Safari.
- **Emulation:** Accurate mobile device emulation (iPhone, Android) for responsive testing.

## Integration Strategy

### 1. Tooling Setup (MCP)
Playwright provides an MCP server that exposes browser interaction capabilities as tools.
- Gemini CLI will load the Playwright MCP server to gain "browser vision."
- This allows Gemini to execute `click`, `fill`, `navigate`, and `screenshot` operations directly during a debugging or development session.

### 2. Implementation Workflow
Gemini CLI will drive the following automated loop:

1.  **Requirement Capture:** Gemini CLI reads the project's task spec or `memory-bank`.
2.  **Test Planning:** Gemini invokes the **Playwright Planner** to explore the target URL and generate `docs/tests/plan.md`.
3.  **Implementation:** Gemini feeds the plan to the **Playwright Generator** to produce the corresponding Playwright test files in `scripts/tests/e2e/`.
4.  **Verification & Healing:** Gemini executes the tests. If a failure occurs, it invokes the **Playwright Healer** to diagnose and repair the test code automatically.

### 3. Setup Commands
To initialize the agent definitions and tools within the `k3d-manager` repository:

```bash
# Initialize Playwright Agent definitions (using Claude loop compatibility if Gemini is not yet native)
npx playwright init-agents --loop=claude
```

## Success Metrics
- **Zero-touch Test Creation:** 100% of basic UI tests generated from a simple natural language prompt.
- **Auto-healing:** At least 80% of selector-related test failures resolved by the Healer without human intervention.
- **Context Efficiency:** Reduced token usage by offloading "blind" browser exploration to specialized agents.
