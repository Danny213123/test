# The Monolithic Architecture of rocm-blogs-sphinx
## Why It Is Harmful to Development

> **Audience:** Engineering Leadership & Platform Team
> **Date:** February 12, 2026

---

## Executive Summary

The `rocm-blogs-sphinx` package — the custom Sphinx extension powering the current ROCm blog platform — exhibits every hallmark of **monolithic anti-design**: god files, mega-functions, global mutable state, tight coupling, no separation of concerns, and no testable boundaries.

But the problems run deeper than just the extension code. **Sphinx itself is a monolithic workflow engine built on top of Docutils** — a document-processing library designed in 2001 that enforces a rigid, sequential pipeline. This foundation makes it architecturally impossible to build modern, interactive UI elements. Every "feature" must be shoehorned through a pipeline that was designed to produce static reference documentation, not dynamic web experiences.

This document quantifies these structural problems with concrete evidence from the codebase and explains why this architecture impedes development velocity, reliability, and maintainability.

---

## 1. Sphinx Is a Sequential Docutils Pipeline — Not a Web Framework

### 1.1 The Docutils Foundation

Sphinx is not a standalone tool — it is a wrapper around **Docutils**, a Python library created in 2001 for converting reStructuredText into output formats like HTML and LaTeX. Every document Sphinx processes passes through Docutils' internal pipeline, which executes as a **strict sequence of phases**:

```
                    Docutils Sequential Pipeline
                    ============================

  .rst / .md file
       │
       ▼
  ┌─────────────┐
  │  1. Parser   │  Convert markup to a document tree (docutils nodes)
  └──────┬──────┘
         ▼
  ┌─────────────┐
  │ 2. Transforms│  Resolve references, apply substitutions (sequential)
  └──────┬──────┘
         ▼
  ┌─────────────┐
  │  3. Writer   │  Serialize document tree to HTML strings
  └──────┬──────┘
         ▼
    Static .html file
```

Each phase must complete before the next begins. There is no streaming, no incremental output, and no way to interleave phases across documents. Docutils processes **one document at a time, one phase at a time**.

### 1.2 Sphinx Adds More Sequential Phases

Sphinx wraps Docutils and adds its own layers, extending the sequential pipeline to **8+ phases**:

| Phase | What Happens | Parallelizable? |
|---|---|---|
| 1. **Config** | Read `conf.py`, initialize extensions | No |
| 2. **Builder Init** | Fire `builder-inited` event, run all connected handlers | No (sequential event chain) |
| 3. **Environment Setup** | Scan source files, check modification times | No |
| 4. **Read** (Docutils) | Parse each document → Docutils node tree | Limited (`parallel_read_safe`) |
| 5. **Transforms** | Cross-reference resolution, TOC tree construction | No |
| 6. **Resolve** | Resolve pending references across all documents | No (requires full site context) |
| 7. **Write** (Docutils) | Serialize each document tree → HTML | **No** (`parallel_write_safe: False`) |
| 8. **Finish** | Copy static files, run post-processing | No |

In `rocm-blogs-sphinx`, **seven functions** are all wired to the same `builder-inited` event and execute sequentially:

```python
# __init__.py — _register_event_handlers()
# All 7 handlers fire on "builder-inited", one after another:
sphinx_app.connect("builder-inited", run_metadata_generator)     # 1
sphinx_app.connect("builder-inited", update_index_file)          # 2
sphinx_app.connect("builder-inited", blog_generation)            # 3
sphinx_app.connect("builder-inited", update_posts_file)          # 4
sphinx_app.connect("builder-inited", update_vertical_pages)      # 5
sphinx_app.connect("builder-inited", update_category_pages)      # 6
sphinx_app.connect("builder-inited", update_category_verticals)  # 7
sphinx_app.connect("build-finished", log_total_build_time)
```

These 7 functions — totaling over **3,000 lines** — run back-to-back in a single Python thread. If handler #2 takes 60 seconds, handlers #3–#7 wait. There is no concurrency, no fan-out, and no way to run them in parallel because the extension declares `parallel_write_safe: False` and they all share global mutable state.

### 1.3 The GIL Makes It Worse

Even if Sphinx wanted to parallelize, Python's **Global Interpreter Lock (GIL)** means only one thread can execute Python bytecode at a time. The `ThreadPoolExecutor` used in `process.py` and `_rocmblogs.py` provides concurrency for I/O-bound work (file reads), but **zero parallelism for CPU-bound work** like HTML string construction, template rendering, and image path resolution — which is where the majority of the build time is spent.

### 1.4 Comparison to Modern Build Pipelines

| Capability | Sphinx/Docutils | Vite / esbuild (React Platform) |
|---|---|---|
| File processing | Sequential, single-threaded Python | Parallel, multi-threaded native code (Go/Rust) |
| Incremental builds | Partial (re-reads changed files, but re-resolves everything) | Full (HMR updates only the changed module) |
| Build feedback loop | **>7 minutes** (full pipeline, every time) | **<1 second** (HMR) or **<10 seconds** (full build) |
| Output format | Static HTML strings written to disk | ES modules served from memory, lazy-loaded |
| Plugin execution | Sequential event hooks in Python | Parallel transform plugins in native code |
| Cache invalidation | Coarse-grained (often rebuilds everything) | Fine-grained (per-module dependency graph) |

---

## 2. Why Modern UI Development Is Impossible in Sphinx

The sequential Docutils pipeline is not just slow — it makes entire categories of modern web functionality **architecturally impossible**.

### 2.1 No Client-Side State Management

Sphinx produces **static HTML files**. Once a page is rendered, it is a flat document with no runtime state. Modern UI patterns require client-side state:

| Feature | Requires | Sphinx Can Do This? |
|---|---|---|
| Search-as-you-type | Client-side index + reactive updates | **No** — search is server-side or absent |
| Infinite scroll / pagination | Dynamic DOM updates on scroll events | **No** — pages are pre-rendered with fixed content |
| Theme toggle (light/dark) | CSS variable swap + persisted preference | **Hacky** — requires injected `<script>` tags |
| Reading progress indicator | Scroll position tracking + UI update | **No** — no framework for reactive UI |
| Comments / discussions | Real-time data fetching + rendering | **No** — static HTML cannot fetch data |
| Animated carousels | State machine for slides + CSS transitions | **Painful** — requires 269 lines of inline `<script>` (see `banner-slider.html`) |

In `rocm-blogs-sphinx`, every interactive feature is achieved by **manually injecting `<script>` tags** into Jinja2 templates — bypassing Sphinx entirely and writing raw JavaScript with no build tooling, no type checking, no module system, and no HMR.

### 2.2 No Component Model

Modern web development is built on **components** — reusable, composable units of UI with defined inputs (props), local state, and lifecycle methods. Sphinx has no concept of components.

**What Sphinx has instead:**

- **Docutils nodes** — an abstract tree of document elements (paragraphs, sections, lists). These map to document structure, not UI components. There is no "BlogCard" node, no "FeaturedBanner" node, no "SearchResult" node.
- **Directives** — Python classes that produce docutils nodes. A directive takes raw text parameters, creates nodes, and inserts them into the document tree. Directives cannot manage state, handle events, or compose with other directives at the UI level.
- **Jinja2 templates** — server-side templates that render the final HTML. Templates can include other templates via `{% include %}`, but this is string concatenation, not component composition. There are no props, no slots, no lifecycle hooks.

**The result:** To build a "blog card" in Sphinx, you write a Python function that constructs an HTML string. To build a "blog card" in React, you write a typed component:

```
Sphinx approach (grid.py):                  React approach (BlogCard.tsx):
  Python function                             TypeScript component
  → reads blog data                           → receives typed props
  → constructs HTML string                    → returns JSX
  → injects CSS via string concat             → CSS modules / Tailwind
  → returns raw string to Jinja2              → React handles rendering
  → no type safety                            → full type safety
  → no reuse without copy-paste               → import and compose anywhere
  → 570 lines                                 → 83 lines
```

### 2.3 No Modern CSS Tooling

Sphinx themes use **static CSS files** loaded at build time. There is no:

- **CSS Modules** — scoped styles per component
- **Utility-first CSS** (e.g., Tailwind) — composable, purged, optimized
- **CSS-in-JS** — co-located styles with component logic
- **Auto-prefixing** — vendor prefix management
- **Tree-shaking** — dead CSS elimination
- **Hot reloading** — instant style updates during development

In `rocm-blogs-sphinx`, the `banner-slider.css` file is **671 lines** with manually duplicated styles for light and dark themes. Every `@media` breakpoint is written twice. There is no design token system, no variable-based theming, and no way to scope styles to a single component.

### 2.4 No JavaScript Build Pipeline

Any interactivity in Sphinx requires handwritten `<script>` tags with:

- **No module system** — no `import/export`, no code splitting, no tree-shaking
- **No TypeScript** — no type checking, no autocomplete, no refactoring safety
- **No bundling** — every script is loaded as a separate HTTP request
- **No minification** — raw source code is shipped to production
- **No source maps** — debugging in production requires reading minified code (except there is none)
- **No hot module replacement** — every change requires a full 7-minute rebuild

The 269-line inline `<script>` in `banner-slider.html` — which implements carousel auto-advance, progress bars, visibility API handling, and responsive breakpoints — is a textbook example. This logic would be ~15 lines in a React component using `useState`, `useEffect`, and CSS `animation-play-state`.

### 2.5 The Extension Escape Hatch Is Worse

When Sphinx cannot natively support a feature, the only option is to write a **Sphinx extension** — a Python module that hooks into the Docutils pipeline. Extensions must:

1. Register custom docutils nodes (Python classes)
2. Define custom directives (more Python classes that manipulate the node tree)
3. Add visitor methods for each output format (HTML visitor, LaTeX visitor, etc.)
4. Hook into Sphinx events to inject CSS/JS at the right pipeline phase
5. Handle cross-document references manually

This is the equivalent of writing a kernel driver when you need a button to change color. A task that takes 5 minutes in React (add an `onClick` handler, update state, re-render) requires hundreds of lines of Python pipeline integration in Sphinx — code that can only be tested by running a full build.

### 2.6 What This Means in Practice

Features that are **trivial in React** but **impossible or prohibitively expensive in Sphinx**:

| Feature | React Implementation | Sphinx Feasibility |
|---|---|---|
| Client-side full-text search | `MiniSearch` + `useState` (~60 lines) | Not possible without external service |
| Animated page transitions | `framer-motion` or CSS transitions | Not possible (full page reloads) |
| Lazy-loaded images with blur-up | `<img loading="lazy">` + CSS | Requires custom extension + injected JS |
| Keyboard-navigable search | `onKeyDown` handler + focus management | Would require custom JS injection |
| Responsive sidebar with collapse | `useState` + CSS media queries | Requires template override + custom JS |
| Social share with copy-to-clipboard | `navigator.clipboard.writeText()` | Requires inline `<script>` per page |
| Reading time estimate | `Math.ceil(wordCount / 200)` in component | Requires Python extension + template variable |
| Related posts carousel | Component with props + CSS scroll-snap | Requires custom extension + 500+ lines |
| Real-time content filtering | `Array.filter()` + re-render | Not possible (static HTML) |
| Dark mode with system preference | `matchMedia` + CSS variables | Requires override of entire theme |

---

## 3. The God File: `__init__.py`

The extension's entry point, `__init__.py`, is a single Python file spanning **4,667 lines** and **181 KB**. For context, the entire Linux kernel's `init/main.c` — which boots an operating system — is under 1,500 lines.

This one file contains:

| Function | Lines | Responsibility |
|---|---|---|
| `update_index_file()` | **1,041** | Index page generation, grid layout, featured content, CSS injection, template rendering, image processing, pagination |
| `_generate_banner_slider()` | **528** | Banner carousel HTML generation, image path resolution, WebP conversion, slide navigation markup |
| `blog_statistics()` | **457** | Statistics page generation, author counts, category analysis, HTML table generation |
| `update_author_files()` | **342** | Author page generation, blog-author association, image processing |
| `update_vertical_pages()` | **336** | Vertical market page generation, category filtering, pagination |
| `update_posts_file()` | **319** | Paginated posts page generation, lazy loading markup |
| `blog_generation()` | **293** | Blog page styling, CSS injection, social bar generation, OpenGraph metadata |
| `update_category_pages()` | **184** | Category page generation with pagination |
| `setup()` | **82** | Extension registration, event handler wiring |
| 10+ utility functions | ~1,085 | Logging, timing, profiling, HTML cleaning |
| **Total** | **4,667** | Everything |

### Why This Is Harmful

1. **No developer can hold this in their head.** A 4,667-line file with 31 functions that share global state is impossible to reason about locally. Any change to one function may have invisible side effects on another.

2. **Git merge conflicts are inevitable.** With every feature, bug fix, and styling change landing in the same file, parallel development produces constant merge conflicts. Two developers cannot work on "the banner" and "the category page" simultaneously without conflicting.

3. **Code review is impractical.** A pull request that touches `__init__.py` forces reviewers to scan thousands of lines of context to understand the impact of a 5-line change.

---

## 4. Mega-Functions: 500-1,300 Lines Per Function

Individual functions within the monolith are themselves monolithic.

### `update_index_file()` — 1,041 Lines

This single function is responsible for:
- Reading the index template
- Generating featured grid items
- Generating category grid items
- Generating "latest" grid items
- Building the featured slider
- Injecting CSS from multiple files
- Processing image paths and WebP conversion
- Creating pagination controls
- Writing the final index file

A function this large cannot be unit-tested, debugged in isolation, or safely modified without understanding all 1,041 lines. It has **no return type annotation**, **no interface contract**, and **no separation between data retrieval, business logic, and HTML generation**.

### `metadata_generator()` — 1,325 Lines (`metadata.py`)

A single function that:
- Reads every blog file
- Extracts YAML frontmatter
- Classifies tags into market verticals
- Resolves author information
- Generates JSON metadata files
- Creates CSV exports
- Writes diagnostic logs

This function is **longer than the entire React `BlogPost.tsx` component** (861 lines), which handles rendering an entire blog post with math, code highlighting, Mermaid diagrams, comments, social sharing, and related posts.

### `_process_category()` — 501 Lines (`process.py`)

Generates a single category page. Takes **10 parameters**, including a log file handle that must be threaded through every call:

```python
def _process_category(
    category_info,          # dict
    rocm_blogs,             # ROCmBlogs singleton
    blogs_directory,        # str
    pagination_template,    # str (raw HTML)
    css_content,            # str (raw CSS)
    pagination_css,         # str (more raw CSS)
    current_datetime,       # datetime
    category_template,      # str (raw HTML template)
    category_blogs=None,    # Optional[list]
    log_file_handle=None,   # Optional[file handle]
):
    # 501 lines of interleaved concerns...
```

---

## 5. The Full Monolith: 12,500+ Lines Across 9 Files

| File | Lines | Bytes | Primary Responsibility |
|---|---|---|---|
| `__init__.py` | 4,667 | 181 KB | Everything (see above) |
| `metadata.py` | 1,654 | 73 KB | Tag classification, metadata generation |
| `process.py` | 1,518 | 64 KB | Blog processing, social sharing, category pages |
| `holder.py` | 1,178 | 45 KB | Blog collection management, featured blogs, CSV I/O |
| `banner.py` | 757 | 25 KB | Banner slide HTML generation |
| `_rocmblogs.py` | 613 | 22 KB | Blog discovery, metadata extraction |
| `grid.py` | 570 | 23 KB | Grid item HTML generation |
| `blog.py` | ~560 | 22 KB | Blog data model |
| `images.py` | ~700 | 28 KB | Image processing, WebP conversion |
| **Total** | **~12,200+** | **~483 KB** | **The entire platform** |

For comparison, the **entire React platform** — which includes routing, search, comments, theming, code highlighting, math rendering, analytics, and the build pipeline — ships a `src/` directory of similar total size but divided into **50+ focused files** averaging ~100 lines each.

---

## 6. Global Mutable State

The codebase relies on **global variables** that any function can read or write at any time:

```python
# __init__.py — global state
_CRITICAL_ERROR_OCCURRED = False          # modified by setup(), checked everywhere
_BUILD_START_TIME = time.time()           # set once, read globally
_BUILD_PHASES = {"setup": 0, ...}         # mutated by every phase function
_current_sphinx_app = None                # global reference to Sphinx app
structured_logger = None                  # global logger instance
```

### Why This Is Harmful

- **Functions have hidden inputs.** A function signature like `blog_statistics(sphinx_app, rocm_blogs)` appears to take two inputs. In reality, it reads and writes global state (`_BUILD_PHASES`, `_CRITICAL_ERROR_OCCURRED`), making its true behavior dependent on the order of execution.
- **Non-deterministic behavior.** If any function sets `_CRITICAL_ERROR_OCCURRED = True`, downstream functions may silently skip work or produce partial output — with no explicit error propagation.
- **Parallelism is impossible.** The extension declares `parallel_write_safe: False`, meaning Sphinx cannot parallelize the write phase. This is a direct consequence of global mutable state — the code would produce race conditions if run in parallel.

---

## 7. Wildcard Imports: No Encapsulation

The codebase uses `from .module import *` extensively:

```python
# __init__.py imports
from .banner import *
from .constants import *
from .images import *
from .logger.logger import *
from .metadata import *
from .process import *
```

```python
# process.py imports
from ._rocmblogs import *
from .constants import *
from .grid import *
from .images import *
from .logger.logger import *
from .utils import *
```

### Why This Is Harmful

- **Namespace pollution.** Every public symbol from every module is dumped into every file's namespace. There is no way to know where a function is defined without searching the entire codebase.
- **Silent shadowing.** If two modules define a function with the same name, one silently overwrites the other. There is no error, no warning, and no way to detect this statically.
- **No interface boundaries.** Every module can access every function in every other module. There is no concept of public vs. private APIs, no encapsulation, and no dependency direction.
- **Refactoring is dangerous.** Renaming or removing a function in one file can break any other file in the package — and the breakage won't be detected until runtime, during a 7-minute build.

---

## 8. HTML Generation via Python String Formatting

The entire UI layer is generated by Python functions constructing raw HTML strings:

```python
# grid.py — 570 lines to generate one blog card
grid_template = """
:::{grid-item-card}
:padding: 1
:img-top: {image}
+++
<a href="{href}" class="small-card-header-link">
    <h2 class="card-header">{title}</h2>
</a>
<p class="paragraph">{description}</p>
<div class="date">{date} {authors_html}</div>
:::
"""
grid_content = grid_template.format(
    title=title, date=date, description=description,
    authors_html=authors_html, image=image, href=href,
)
```

### Why This Is Harmful

- **No type safety.** If a template expects `{title}` but the code passes `heading`, the error is a runtime `KeyError` — discovered only after a 7-minute build.
- **No syntax validation.** Malformed HTML (unclosed tags, invalid attributes) is invisible until the page renders in a browser.
- **No component reuse.** The "blog card" HTML is duplicated and slightly modified in `grid.py`, `process.py`, and `__init__.py`. Changes must be synchronized manually across all three.
- **CSS is injected by reading files at build time.** Styling is loaded via `import_file()` in Python and concatenated into template strings. There is no CSS tooling, no minification, no tree-shaking, no dead-code elimination.

---

## 9. Tight Coupling to Sphinx Internals

Every function takes a `Sphinx` application object and directly accesses its internal state:

```python
def update_index_file(sphinx_app: Sphinx, rocm_blogs: ROCmBlogs = None):
    # Direct access to Sphinx internals
    src_dir = sphinx_app.srcdir
    out_dir = sphinx_app.outdir
    config = sphinx_app.config
    env = sphinx_app.env
    # ... 1,041 lines of logic coupled to these internals
```

### Why This Is Harmful

- **Cannot run without Sphinx.** No function can be tested, debugged, or executed outside of a full Sphinx build cycle. There is no CLI, no REPL, and no isolated test harness.
- **Sphinx version upgrades are breaking.** Any change to Sphinx's internal API (which is not guaranteed stable) can break the extension. The extension is coupled to undocumented Sphinx internals, not to a stable public API.
- **Testing requires the entire build.** To verify a 1-line CSS change, you must run a full 7-minute Sphinx build. There is no way to unit-test a grid card, a banner slide, or a category page in isolation.

---

## 10. No Test Suite

The `test/` directory contains **zero unit tests** for the core logic. There are no tests for:
- Grid item generation
- Banner slide construction
- Category page pagination
- Image path resolution
- Metadata extraction
- Tag classification
- Author file generation

The only verification method is: run a 7-minute build, then visually inspect the output in a browser. There is no regression safety net, no CI test gate, and no way to determine if a change broke something without manually reviewing every page.

---

## 11. Consequences for Development Velocity

| Activity | Time with Monolith | Time with Modular Architecture |
|---|---|---|
| Understand where to make a change | 30-60 min (search 4,667-line file) | 2-5 min (find focused component) |
| Make the change | 5 min | 5 min |
| Verify the change | 7 min (full Sphinx build) | <1 sec (HMR) or 5 sec (unit test) |
| Code review | 30+ min (reviewer must understand entire file) | 5-10 min (focused diff, clear boundaries) |
| Resolve merge conflicts | 15-30 min (high conflict rate in monolith) | Rare (modules are independent) |
| Debug a regression | 1-4 hours (no tests, no isolation) | 10-30 min (run failing test, inspect component) |
| **Total per feature** | **~3-6 hours** | **~30-60 minutes** |

---

## 12. Summary: The Architecture Comparison

```
rocm-blogs-sphinx (Monolith)          React Platform (Modular)
                                      
+-------------------------+           +------+ +------+ +------+
|                         |           | Blog | |Banner| |Search|
|   __init__.py           |           | Card | |      | |      |
|   4,667 lines           |           | 83L  | | 133L | | 60L  |
|   31 functions          |           +--+---+ +--+---+ +--+---+
|   global state          |              |        |        |
|   HTML generation       |           +--+--------+--------+--+
|   CSS injection         |           |     Page Components   |
|   image processing      |           |     (typed props)     |
|   pagination            |           +----------+------------+
|   category logic        |                      |
|   author logic          |           +----------+------------+
|   statistics            |           |    Services & Utils   |
|   banner logic          |           |    (pure functions)   |
|   vertical logic        |           +----------+------------+
|   template rendering    |                      |
|   metadata              |           +----------+------------+
|   logging               |           |    Build Pipeline     |
|   timing                |           |    (scripts/)         |
|                         |           +-----------------------+
+-------------------------+
  Everything coupled              Each box: independent, testable,
  to everything else.             replaceable, reviewable.
```

---

## Conclusion

The `rocm-blogs-sphinx` extension is a **textbook example of monolithic software architecture** — a design pattern that the software industry has spent two decades learning to avoid. Its 12,500+ lines of tightly coupled Python, global mutable state, mega-functions, zero test coverage, and tight coupling to Sphinx internals create a development environment where:

- **Every change is risky** — because there are no tests and no isolation.
- **Every change is slow** — because verification requires a 7-minute full build.
- **Every change is painful** — because the code is dense, coupled, and undocumented.
- **Parallel development is impossible** — because everything lives in one file and shares global state.

Modern software engineering has moved to modular, component-based architectures specifically to eliminate these problems. The React platform's 50+ focused, typed, tested components — averaging ~100 lines each — demonstrate how the same functionality can be delivered in a fraction of the code with dramatically better developer experience.
