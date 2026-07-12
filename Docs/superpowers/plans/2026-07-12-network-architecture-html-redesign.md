# Network Architecture HTML Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `/Users/flo/Downloads/schema-architecture-reseau.html` as a clear, modern, self-contained architecture document while preserving every technical datum.

**Architecture:** Keep one autonomous HTML file and reorganize it into a semantic hero, sticky section navigation, executive comparison, layered diagrams, migration cards, and responsive technical tables. CSS variables provide a consistent visual language for infrastructure, legacy risks, and target-state recommendations.

**Tech Stack:** Semantic HTML5, embedded CSS, existing inline SVG, minimal embedded JavaScript for progressive navigation only.

## Global Constraints

- Preserve all equipment names, port identifiers, VLANs, VDOMs, routes, policies, addresses, scenarios, warnings, and source references from the existing document.
- The final deliverable remains a single HTML file at `/Users/flo/Downloads/schema-architecture-reseau.html`.
- It must remain understandable offline and printable.
- It must adapt to desktop, tablet, and mobile widths.

---

### Task 1: Semantic shell and visual system

**Files:**
- Modify: `/Users/flo/Downloads/schema-architecture-reseau.html`

**Interfaces:**
- Consumes: existing HTML content and inline SVG diagrams.
- Produces: `.site-nav`, `.hero`, `.executive-grid`, semantic section anchors, and the shared CSS design tokens used by all later sections.

- [ ] **Step 1: Run a failing structural assertion**

```bash
python3 -c "from pathlib import Path; s=Path('/Users/flo/Downloads/schema-architecture-reseau.html').read_text(); assert '<nav class=\"site-nav\"' in s and 'id=\"synthese\"' in s"
```

Expected: `AssertionError`, because the new semantic shell is absent.

- [ ] **Step 2: Replace the dark blueprint stylesheet and ASCII banner**

Add the light visual tokens, responsive typography, cards, navigation, diagram frames, tables, print rules, and reduced-motion rule. Replace the banner with a semantic hero and add navigation anchors.

- [ ] **Step 3: Verify the structural assertion passes**

Run the Step 1 command again. Expected: exit code 0.

### Task 2: Readability and information hierarchy

**Files:**
- Modify: `/Users/flo/Downloads/schema-architecture-reseau.html`

**Interfaces:**
- Consumes: shared CSS tokens and all original technical content.
- Produces: executive comparison cards, section headers, flow summaries, callouts, and clearer diagram framing.

- [ ] **Step 1: Run a failing content assertion**

```bash
python3 -c "from pathlib import Path; s=Path('/Users/flo/Downloads/schema-architecture-reseau.html').read_text(); assert 'En 30 secondes' in s and '7 étapes' in s and '3 étapes' in s"
```

Expected: `AssertionError`, because the executive comparison is absent.

- [ ] **Step 2: Add the executive comparison and navigation IDs**

Create a concise comparison of current and target flows without removing the detailed diagrams, inventories, scenarios, or address plan.

- [ ] **Step 3: Verify the content assertion passes**

Run the Step 1 command again. Expected: exit code 0.

### Task 3: Validate structure, preservation, responsiveness, and print output

**Files:**
- Verify: `/Users/flo/Downloads/schema-architecture-reseau.html`

**Interfaces:**
- Consumes: final HTML.
- Produces: verification evidence for structure and preservation.

- [ ] **Step 1: Parse the file and verify closing structure**

```bash
python3 -c "from html.parser import HTMLParser; from pathlib import Path; s=Path('/Users/flo/Downloads/schema-architecture-reseau.html').read_text(); HTMLParser().feed(s); assert s.count('<html') == 1 and s.count('</html>') == 1"
```

Expected: exit code 0.

- [ ] **Step 2: Verify representative technical details remain**

```bash
python3 -c "from pathlib import Path; s=Path('/Users/flo/Downloads/schema-architecture-reseau.html').read_text(); required=['NIAFORTIARC1','SWSM3B','SWSM4S','1/E22 + 2/E22','172.29.247.20','180.45.0.0/16','10.45.0.0/16','NIAFORTIEMEA','1 116']; assert all(x in s for x in required)"
```

Expected: exit code 0.

- [ ] **Step 3: Verify responsive and print rules exist**

```bash
python3 -c "from pathlib import Path; s=Path('/Users/flo/Downloads/schema-architecture-reseau.html').read_text(); assert '@media (max-width: 760px)' in s and '@media print' in s and 'prefers-reduced-motion' in s"
```

Expected: exit code 0.
