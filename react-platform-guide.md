# React Blog Platform — Complete Technical Guide

> **Platform**: ROCm Blog Platform  
> **Version**: `2026.2.11-r.1` (CalVer)  
> **Stack**: React 18 · TypeScript 5.9 · Vite 7 · Tailwind CSS 4 · MyST Markdown  
> **Hosting**: Firebase Hosting (SPA)  
> **Content Source**: GitHub API (live) / Local filesystem (dev)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Project Structure](#2-project-structure)
3. [Getting Started](#3-getting-started)
4. [How the Dev Server Works](#4-how-the-dev-server-works)
5. [The Build Pipeline](#5-the-build-pipeline)
6. [Content System — MyST Markdown](#6-content-system--myst-markdown)
7. [Component Architecture](#7-component-architecture)
8. [Routing & Navigation](#8-routing--navigation)
9. [Search Engine](#9-search-engine)
10. [Type System](#10-type-system)
11. [Configuration & Environment](#11-configuration--environment)
12. [Styling Architecture](#12-styling-architecture)
13. [Performance Architecture](#13-performance-architecture)
14. [Testing](#14-testing)
15. [CI/CD Pipeline](#15-cicd-pipeline)
16. [Deployment](#16-deployment)
17. [Developer Workflow](#17-developer-workflow)
18. [Comparison: React vs Sphinx](#18-comparison-react-vs-sphinx)

---

## 1. Architecture Overview

The platform is a **single-page application (SPA)** that serves technical blog content. Unlike the Sphinx monolith it replaces, it separates concerns into distinct layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Firebase Hosting                         │
│                     (SPA rewrite → index.html)                  │
├─────────────────────────────────────────────────────────────────┤
│                         React 18 SPA                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Router   │  │  Pages   │  │Components│  │   Services    │  │
│  │(react-    │  │(Home,    │  │(BlogCard,│  │(GitHub API,   │  │
│  │ router    │  │ Blog,    │  │ Header,  │  │ Local FS,     │  │
│  │ dom v7)   │  │ Search)  │  │ Footer)  │  │ Firebase)     │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Utils   │  │  Hooks   │  │  Types   │  │   Workers     │  │
│  │(MyST     │  │(useCode  │  │(BlogMeta,│  │(Prefetch      │  │
│  │ parser,  │  │ Block    │  │ BlogPost)│  │ worker)       │  │
│  │ search,  │  │ Enhancer)│  │          │  │               │  │
│  │ markdown)│  │          │  │          │  │               │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      Build-Time Scripts                         │
│  ┌────────────────────────┐  ┌──────────────────────────────┐  │
│  │ generate-blog-index.ts │  │    prerender-blogs.ts        │  │
│  │ (TF-IDF, HITS,         │  │    (MyST → HTML at build)    │  │
│  │  PageRank, verticals)  │  │                              │  │
│  └────────────────────────┘  └──────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                     Vite 7 Build Tool                           │
│  ┌───────────┐  ┌──────────┐  ┌─────────────────────────────┐ │
│  │  React    │  │ Tailwind │  │  Custom serve-blogs plugin  │ │
│  │  plugin   │  │  plugin  │  │  (dev middleware for /blogs) │ │
│  └───────────┘  └──────────┘  └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Content-as-data**: Blog posts are MyST Markdown files living in a separate Git repository (`ROCm/rocm-blogs`). The platform treats them as data, not source code.
2. **Dual content mode**: In development, content is read from the local filesystem. In production, it can be fetched from the GitHub API or bundled at build time.
3. **Build-time intelligence**: The index generator runs TF-IDF cosine similarity, HITS algorithm, and PageRank on the entire corpus at build time — search and related posts are precomputed, not runtime operations.
4. **Type safety end-to-end**: Every blog, component, and API response is typed with TypeScript interfaces.

---

## 2. Project Structure

```
program-repo/
├── .github/
│   └── workflows/
│       └── ci.yml                    # GitHub Actions CI pipeline
├── public/
│   ├── blogs-index.json              # Generated blog metadata index
│   ├── blogs-prerendered.json        # Pre-rendered blog HTML index
│   └── blogs-content/                # Individual pre-rendered blog files
├── scripts/
│   ├── generate-blog-index.ts        # Blog index + search index generator (759 lines)
│   ├── prerender-blogs.ts            # MyST → HTML pre-renderer (366 lines)
│   ├── copy-blog-assets.mjs          # Post-build asset copier
│   ├── optimize-images.ts            # Sharp-based image optimizer
│   ├── release-calver.mjs            # CalVer release automation
│   └── ...                           # 10 more utility scripts
├── src/
│   ├── App.tsx                        # Root component — routing + layout (78 lines)
│   ├── main.tsx                       # Entry point — React root + Firebase init (44 lines)
│   ├── config.ts                      # Central configuration (45 lines)
│   ├── firebase.ts                    # Firebase SDK initialization
│   ├── index.css                      # Global styles + CSS custom properties
│   ├── vite-env.d.ts                  # Vite type declarations
│   ├── components/
│   │   ├── BlogCard.tsx / .css        # Individual blog card (2.8 KB)
│   │   ├── BlogGrid.tsx / .css        # Paginated blog grid (7.7 KB)
│   │   ├── BlogPost.tsx / .css        # Full blog post renderer (46.6 KB)
│   │   ├── CardSlider.tsx / .css      # Horizontal card carousel (5.4 KB)
│   │   ├── CodeBlock.tsx / .css       # Syntax-highlighted code block (7.4 KB)
│   │   ├── CommentsSection.tsx / .css # Giscus comments integration (2.7 KB)
│   │   ├── CommunitySidebar.tsx / .css# Right sidebar for community articles (5.1 KB)
│   │   ├── FeaturedBanner.tsx / .css  # Hero banner carousel (4.8 KB)
│   │   ├── Footer.tsx / .css          # Site footer (2.2 KB)
│   │   ├── Header.tsx / .css          # Site header + search + nav (22.8 KB)
│   │   └── ui/                        # Radix UI + shadcn primitives
│   │       ├── button.tsx             # Button component (1.5 KB)
│   │       ├── dropdown-menu.tsx      # Dropdown menu (2.3 KB)
│   │       ├── scroll-area.tsx        # Custom scrollbar area (1.4 KB)
│   │       └── sidebar.tsx            # Collapsible sidebar (10.4 KB)
│   ├── hooks/
│   │   └── useCodeBlockEnhancer.ts   # Code block copy/language badge hook (8.5 KB)
│   ├── lib/
│   │   └── utils.ts                   # Tailwind merge utility
│   ├── pages/
│   │   ├── HomePage.tsx / .css        # Landing page with featured + grids (11.4 KB)
│   │   ├── BlogPage.tsx               # Blog post page wrapper (0.6 KB)
│   │   ├── CategoryPage.tsx / .css    # Category listing page (3.1 KB)
│   │   ├── SearchResultsPage.tsx / .css# Search results with highlighting (19.5 KB)
│   │   ├── BlogStatisticsPage.tsx / .css# Analytics dashboard (8.1 KB)
│   │   └── DevPage.tsx / .css         # Developer tools page (2.3 KB)
│   ├── services/
│   │   ├── github.ts                  # GitHub API content service (10.5 KB)
│   │   └── local.ts                   # Local/bundled content service (29.8 KB)
│   ├── styles/
│   │   └── myst-content.css           # MyST-rendered content styles (53.2 KB)
│   ├── types/
│   │   └── blog.ts                    # Core type definitions (1.6 KB)
│   ├── utils/
│   │   ├── markdown.ts                # Markdown processing utilities (52.4 KB)
│   │   ├── myst-parser.ts             # MyST directive/role parser (34.1 KB)
│   │   ├── myst-parser.test.ts        # Parser test suite (7.8 KB)
│   │   ├── search.ts                  # Search utilities — stemming, synonyms (6.4 KB)
│   │   ├── reading.ts                 # Reading time estimation (0.5 KB)
│   │   └── blogPrefetch.ts            # Navigation cache warming (0.7 KB)
│   └── workers/
│       └── prefetch.worker.ts         # Web Worker for background prefetch (1.5 KB)
├── package.json                       # Dependencies + scripts (3.5 KB)
├── vite.config.ts                     # Vite configuration + blog plugin (6.7 KB)
├── firebase.json                      # Firebase Hosting config
├── tsconfig.json                      # TypeScript base config
├── tsconfig.app.json                  # App TypeScript config
├── tsconfig.node.json                 # Node scripts TypeScript config
└── eslint.config.js                   # ESLint flat config
```

---

## 3. Getting Started

### Prerequisites

- **Node.js 20+** (LTS recommended)
- **npm** (comes with Node.js)
- **Git** (for cloning blog content)

### Initial Setup

```bash
# 1. Clone the platform repository
git clone https://github.com/Danny213123/program-repo.git
cd program-repo

# 2. Install dependencies
npm install

# 3. Clone the blog content (the blogs live in a separate repo)
git clone --depth 1 https://github.com/ROCm/rocm-blogs.git blogs

# 4. Generate the blog index (scans blogs/ and creates public/blogs-index.json)
npm run generate-index

# 5. Start the development server
npm run dev
```

The dev server starts at `http://localhost:5173` with hot module replacement (HMR). Changes to any `.tsx`, `.css`, or `.ts` file reflect instantly in the browser.

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `VITE_GITHUB_REPO` | `ROCm/rocm-blogs` | GitHub repo to fetch content from |
| `VITE_GITHUB_BRANCH` | `release` | Branch to fetch from |
| `VITE_USE_LOCAL_CONTENT` | `false` | Use bundled content instead of GitHub API |
| `BLOGS_DIR` | Auto-detected | Path to local blogs directory |
| `BUILD_DIR` | `_build/` | Path to MyST build output |

### Available Scripts

| Command | Description |
|---|---|
| `npm run dev` | Generate index → start Vite dev server |
| `npm run dev:myst` | Build MyST HTML → generate index → start Vite |
| `npm run build` | Full production build (MyST → index → prerender → TypeScript → Vite → copy assets) |
| `npm run test` | Run Vitest test suite |
| `npm run test:watch` | Run tests in watch mode |
| `npm run lint` | Run ESLint |
| `npm run format` | Format all files with Prettier |
| `npm run format:check` | Check formatting without modifying |
| `npm run preview` | Preview the production build locally |
| `npm run build:blogs` | Build blogs with MyST (`npx myst build --html`) |
| `npm run generate-index` | Regenerate `public/blogs-index.json` |
| `npm run prerender-blogs` | Pre-render all blogs to HTML |
| `npm run optimize-thumbnails` | Optimize images with Sharp |
| `npm run release:calver` | Create a CalVer release |
| `npm run commit` | Interactive conventional commit with Commitizen |

---

## 4. How the Dev Server Works

When you run `npm run dev`, four things happen in sequence:

### Step 1: Index Generation (`generate-blog-index.ts`)

The script scans the `blogs/` directory and produces `public/blogs-index.json`:

```
blogs/
├── artificial-intelligence/
│   ├── llm-fine-tuning/
│   │   └── README.md          ← MyST frontmatter + content
│   └── vision-transformers/
│       └── README.md
├── ecosystems-and-partners/
│   └── ...
├── high-performance-computing/
│   └── ...
└── software-tools-optimization/
    └── ...
```

For each `README.md`:
1. **Parse frontmatter** with `gray-matter` (title, date, author, tags, thumbnail, etc.)
2. **Classify market verticals** by mapping tags → verticals (e.g., `PyTorch` → `AI`, `Kubernetes` → `Systems`)
3. **Resolve thumbnail URLs** (checks blog dir, `images/`, `_images/`, shared images)
4. **Build search document** (strip markdown → plain text for indexing)
5. **Embed raw content** (the full markdown is included for instant client-side loading)

After scanning all blogs, the script also:
- **Computes TF-IDF vectors** for every blog
- **Calculates cosine similarity** between all pairs → stores top 5 related posts per blog
- **Runs HITS algorithm** (authority + hub scores) based on cross-references
- **Runs PageRank** for overall importance scoring

Output: `public/blogs-index.json` + `public/search-index.json`

### Step 2: Vite Dev Server

Vite starts with three plugins:

```typescript
export default defineConfig({
  plugins: [react(), tailwindcss(), serveBlogsPlugin()],
  // ...
})
```

The custom `serveBlogsPlugin()` adds middleware that intercepts HTTP requests:

- **`/blogs/*`** → Serves files from the local `blogs/` directory (auto-discovered)
- **`/_build/*`** → Serves MyST build output

This means the React app can `fetch('/blogs/artificial-intelligence/my-post/README.md')` during development and get the file from your local filesystem — no GitHub API needed.

### Step 3: Blog Directory Auto-Discovery

The Vite config automatically finds your blogs directory by checking these locations in order:

1. `BLOGS_DIR` environment variable
2. `./blogs` (project root)
3. `../blogs` (one level up)
4. `../rocm-blogs/blogs` (sibling repo)
5. `../rocm-blogs-internal/blogs` (internal repo)
6. `~/Desktop/rocm-blogs/blogs` (Desktop)
7. Recursive scan of Desktop subdirectories

This means a developer can clone the blog content anywhere and the platform will find it.

### Step 4: HMR + React Fast Refresh

Vite provides sub-second hot module replacement. When you edit:
- A **`.tsx` component** → React Fast Refresh preserves component state
- A **`.css` file** → Styles are injected without full page reload
- A **`config.ts`** → Full module reload

---

## 5. The Build Pipeline

The production build (`npm run build`) runs 5 stages sequentially:

```
npm run build:blogs → npm run generate-index → npm run prerender-blogs → tsc -b → vite build → npm run copy:blog-assets
```

### Stage 1: MyST Build (`npx myst build --html`)

MyST processes every `.md` file and outputs structured HTML in `_build/`. This handles:
- Cross-references between documents
- Bibliography/citation resolution
- Math rendering (KaTeX)
- Custom directive processing

### Stage 2: Index Generation

Same as the dev server step — produces `public/blogs-index.json` with all metadata, search indices, related posts, and link analysis scores.

### Stage 3: Pre-rendering (`prerender-blogs.ts`)

This is the key performance optimization. The script:

1. Reads every blog's `README.md`
2. Processes MyST syntax (math, directives, roles, abbreviations)
3. Renders markdown → HTML using remark + rehype pipeline
4. Writes a **lightweight index** (`blogs-prerendered.json`) with metadata only
5. Writes **individual content files** to `public/blogs-content/{category}--{slug}.json`

This means at runtime, loading a blog post is a single `fetch()` for a JSON file — no markdown parsing in the browser.

### Stage 4: TypeScript Compilation (`tsc -b`)

Type-checks the entire project. Any type error fails the build.

### Stage 5: Vite Build

Vite bundles the application using Rollup with manual chunk splitting:

```typescript
manualChunks: {
  'vendor-react': ['react', 'react-dom', 'react-router-dom'],
  'vendor-utils': ['date-fns', 'gray-matter', 'minisearch'],
}
```

This produces:
- `dist/index.html` — The SPA shell
- `dist/assets/vendor-react-*.js` — React runtime (~140 KB gzipped)
- `dist/assets/vendor-utils-*.js` — Utility libraries
- `dist/assets/index-*.js` — Application code
- `dist/assets/index-*.css` — All styles
- `dist/blogs-index.json` — Blog metadata
- `dist/blogs-content/` — Pre-rendered blog content files

### Stage 6: Asset Copy (`copy-blog-assets.mjs`)

Copies blog images, thumbnails, and static assets from `blogs/` into `dist/blogs/` so they're served alongside the app.

---

## 6. Content System — MyST Markdown

### What Is MyST?

MyST (Markedly Structured Text) is a superset of CommonMark Markdown designed for technical and scientific content. It adds:
- **Directives** (`:::{note}`, `:::{dropdown}`, `:::{code-block}`)
- **Roles** (`{math}`, `{term}`, `{button}`, `{kbd}`)
- **Cross-references** (`{ref}`, `{doc}`)
- **Math** (inline `$...$`, display `$$...$$`, `{math}` role)
- **Frontmatter** (YAML metadata for blog posts)

### Blog Post Structure

Every blog post is a `README.md` in a category subdirectory:

```markdown
---
blogpost: true
blog_title: "Fine-Tuning LLMs on AMD GPUs"
date: "2026-01-15"
author: "Jane Doe, John Smith"
thumbnail: "./images/thumbnail.png"
tags: "LLM, Fine-Tuning, PyTorch, MI300X"
category: "artificial-intelligence"
language: "English"
myst:
  html_meta:
    "description lang=en": "Learn how to fine-tune large language models using ROCm on AMD Instinct MI300X GPUs."
---

# Fine-Tuning LLMs on AMD GPUs

This blog demonstrates how to...

:::{note}
Ensure you have ROCm 6.0+ installed before proceeding.
:::

The equation for attention is:

$$
\text{Attention}(Q, K, V) = \text{softmax}\left(\frac{QK^T}{\sqrt{d_k}}\right)V
$$

```python
import torch
model = AutoModelForCausalLM.from_pretrained("meta-llama/Llama-2-7b")
```
```

### The MyST Parser (`src/utils/myst-parser.ts`)

The platform includes a **772-line custom MyST parser** that handles all MyST syntax client-side. This is a pure TypeScript implementation with no Vite/browser dependencies — it runs identically in both the browser and Node.js (for pre-rendering).

The parser provides 7 exported functions:

| Function | Lines | Purpose |
|---|---|---|
| `escapeHtml()` | 10 | XSS protection for embedded content |
| `parseMystMath()` | 132 | Inline `$...$`, display `$$...$$`, `{math}` role → KaTeX-compatible output |
| `collectMystTargets()` | 21 | Extract `(name)=![alt](url)` target definitions |
| `parseMystDirectives()` | 88 | Line-by-line state machine for `:::{directive}` blocks |
| `generateDirectiveHtml()` | 438 | Convert directive AST to HTML for 20+ directive types |
| `parseMystRoles()` | 47 | Parse inline `{role}\`text\`` syntax |
| `processAbbreviations()` | 13 | Replace abbreviation patterns with `<abbr>` tags |

### Supported Directives

The parser handles these directive types:

| Category | Directives |
|---|---|
| **Admonitions** | `note`, `warning`, `tip`, `important`, `caution`, `danger`, `hint`, `attention`, `error`, `seealso`, `todo` |
| **Layout** | `grid`, `card`, `tab-set`, `tab-item`, `dropdown` |
| **Code** | `code-block`, `code-cell`, `literalinclude`, `mermaid` |
| **Math** | `math` (display block) |
| **Scientific** | `prf:theorem`, `prf:lemma`, `prf:proof`, `prf:definition`, `prf:example`, `exercise`, `solution` |
| **Media** | `image`, `figure`, `video`, `youtube` |
| **Interactive** | `terminal`, `benchmark`, `comparison` |
| **Structure** | `table`, `list-table`, `csv-table`, `glossary`, `toctree` |

---

## 7. Component Architecture

### Component Inventory

The platform has **10 primary components**, each as a `.tsx` + `.css` pair:

#### `BlogCard` (2.8 KB)
A single blog card showing thumbnail, title, description, date, and author. Used everywhere blog posts are displayed — the home page, category pages, search results, related posts.

```tsx
<BlogCard post={post} />
```

This is the React equivalent of the 907-line Sphinx implementation (`grid.py` + `process.py` wrapper #1 + wrapper #2).

#### `BlogGrid` (7.7 KB)
A responsive grid of `BlogCard` components with pagination. Handles:
- Configurable items per page
- Responsive column counts (1 → 2 → 3 → 4 columns)
- Empty state messaging
- Loading skeleton states

#### `BlogPost` (46.6 KB)
The full blog post renderer. This is the most complex component, handling:
- Markdown → HTML rendering (via pre-rendered content or client-side parsing)
- Mermaid diagram initialization
- KaTeX math rendering
- Prism.js syntax highlighting
- Table of contents generation
- Social sharing (Twitter, LinkedIn, copy-to-clipboard)
- Related posts sidebar
- Reading time estimation
- Image zoom/lightbox
- Scroll progress indicator
- Code block copy buttons

#### `CardSlider` (5.4 KB)
A horizontal scrollable carousel for featured blog cards with CSS scroll-snap.

#### `CodeBlock` (7.4 KB)
Enhanced code blocks with:
- Language-specific syntax highlighting
- Copy-to-clipboard button
- Line numbers
- Language badge
- Terminal prompt styling

#### `CommentsSection` (2.7 KB)
Integration with Giscus (GitHub Discussions-based commenting system).

#### `CommunitySidebar` (5.1 KB)
Right sidebar displaying community articles, trending topics, and external links.

#### `FeaturedBanner` (4.8 KB)
Hero carousel on the home page displaying featured blog posts with:
- Auto-advancement timer
- Manual navigation dots
- Progress bar animation
- Responsive image handling

#### `Header` (22.8 KB)
The site header with:
- Client-side search (MiniSearch-powered with fuzzy matching)
- Category navigation
- Theme switching (light/dark/graphite)
- Mobile hamburger menu
- Search results dropdown with keyboard navigation

#### `Footer` (2.2 KB)
Standard site footer with links and copyright.

### UI Primitives (`components/ui/`)

The platform uses **Radix UI** primitives wrapped with **shadcn/ui** conventions:

| Component | Source | Purpose |
|---|---|---|
| `button.tsx` | Radix Slot + CVA | Polymorphic button with variant support |
| `dropdown-menu.tsx` | Radix Dropdown | Accessible dropdown menus |
| `scroll-area.tsx` | Radix ScrollArea | Custom scrollbar styling |
| `sidebar.tsx` | Custom | Collapsible sidebar with mobile sheet overlay |

---

## 8. Routing & Navigation

The app uses **React Router v7** with lazy-loaded page components:

```tsx
// App.tsx — All routes
<Routes>
  <Route path="/"                       element={<HomePage />} />
  <Route path="/category/:category"     element={<CategoryPage />} />
  <Route path="/blogs/:category/*"      element={<BlogPage />} />
  <Route path="/blog/:category/*"       element={<BlogPage />} />
  <Route path="/statistics"             element={<BlogStatisticsPage />} />
  <Route path="/search"                 element={<SearchResultsPage />} />
  <Route path="/dev"                    element={<DevPage />} />
</Routes>
```

### Lazy Loading

Every page component is loaded on demand using `React.lazy()`:

```typescript
const HomePage = lazy(() =>
  import('./pages/HomePage').then((module) => ({ default: module.HomePage }))
)
```

This means the initial bundle only includes the shell (Header + Footer + Router). Page-specific code is fetched when the user navigates to that route. A loading spinner is shown during the chunk download.

### URL Patterns

| URL | Page | Example |
|---|---|---|
| `/` | Home | Landing page with featured banner + grids |
| `/category/artificial-intelligence` | Category | Filtered blog list |
| `/blogs/artificial-intelligence/llm-fine-tuning` | Blog Post | Full article |
| `/blog/artificial-intelligence/llm-fine-tuning` | Blog Post | Alias (backward compat) |
| `/search?q=pytorch+training` | Search Results | Full-text search |
| `/statistics` | Statistics | Blog analytics dashboard |
| `/dev` | Dev Tools | Developer debug page |

### SPA Navigation

Because this is a single-page app, all navigation is client-side. The browser never does a full page reload. Firebase Hosting is configured to rewrite **all** requests to `/index.html`:

```json
{
  "hosting": {
    "rewrites": [{ "source": "**", "destination": "/index.html" }]
  }
}
```

---

## 9. Search Engine

The platform implements a **full client-side search engine** — no backend required.

### Architecture

```
Build time:                          Runtime:
┌──────────────┐                    ┌──────────────────┐
│ generate-    │  blogs-index.json  │ Header.tsx        │
│ blog-index.ts│ ─────────────────→ │                   │
│              │  search-index.json │  ┌──────────────┐ │
│ - strip MD   │                    │  │ MiniSearch    │ │
│ - plain text │                    │  │ (in-memory    │ │
│ - per blog   │                    │  │  full-text    │ │
└──────────────┘                    │  │  index)       │ │
                                    │  └──────────────┘ │
                                    │         │         │
                                    │  ┌──────────────┐ │
                                    │  │ search.ts    │ │
                                    │  │ - stemming   │ │
                                    │  │ - stop words │ │
                                    │  │ - synonyms   │ │
                                    │  │ - boolean ops│ │
                                    │  └──────────────┘ │
                                    └──────────────────┘
```

### Search Features

1. **Stop word filtering**: Common words (`the`, `a`, `is`, `and`, ...) are removed before searching
2. **Porter stemming**: Words are reduced to base forms (`training` → `train`, `optimization` → `optimiz`)
3. **Synonym expansion**: Domain-specific synonyms expand queries automatically:
   ```typescript
   'gpu': ['graphics', 'accelerator', 'cuda', 'rocm', 'hip']
   'ai':  ['artificial intelligence', 'machine learning', 'ml', 'deep learning', 'neural']
   'llm': ['language model', 'gpt', 'transformer', 'llama', 'mistral', 'chatbot']
   ```
4. **Quoted phrase search**: `"fine-tune llama"` searches for the exact phrase
5. **Boolean operators**: `pytorch AND training`, `rocm OR hip`
6. **Fuzzy matching**: MiniSearch handles typos and partial matches
7. **Result highlighting**: Matched terms are highlighted in search results

### How It Works at Runtime

1. On first page load, `blogs-index.json` is fetched and loaded into MiniSearch
2. User types in the search box → `processQuery()` preprocesses the input
3. MiniSearch returns ranked results with scores
4. `SearchResultsPage` displays results with term highlighting
5. Keyboard navigation (↑↓ Enter) works in the search dropdown

---

## 10. Type System

### Core Types (`types/blog.ts`)

```typescript
// Blog metadata — used in lists, grids, cards
interface BlogMeta {
    slug: string;              // URL-safe identifier: "llm-fine-tuning"
    path: string;              // Full path: "artificial-intelligence/llm-fine-tuning"
    category: string;          // One of 4 categories
    title: string;             // Display title
    date: string;              // ISO date string
    author: string;            // Comma-separated author names
    thumbnail: string;         // Relative path to thumbnail image
    thumbnailUrl?: string;     // Resolved URL for the thumbnail
    thumbnailAltUrls?: string[]; // Fallback thumbnail URLs
    tags: string[];            // Array of tags
    description: string;       // Meta description
    language: string;          // "English" or other
    verticals: string[];       // ["AI", "HPC"] — classified market verticals
    rawContent?: string;       // Full markdown for instant loading
    relatedSlugs?: string[];   // Top 5 related posts by TF-IDF similarity
    authorityScore?: number;   // HITS: How often referenced
    hubScore?: number;         // HITS: How well it links to authoritative content
    pageRank?: number;         // Overall importance
}

// Full blog post — extends metadata with rendered content
interface BlogPost extends BlogMeta {
    content: string;           // Rendered HTML content
    rawContent: string;        // Original markdown
    math?: Record<string, string>; // Named math macros
}

// Blog frontmatter — matches YAML structure in README.md
interface BlogFrontmatter {
    blogpost: boolean;
    blog_title: string;
    date: string;
    author: string;
    thumbnail: string;
    tags: string;              // Comma-separated in YAML
    category: string;
    language: string;
    target_audience?: string;
    key_value_propositions?: string;
    math?: Record<string, string>;
    myst?: { html_meta?: { [key: string]: string } };
}

// GitHub API response type
interface GitHubContent {
    name: string;
    path: string;
    sha: string;
    size: number;
    url: string;
    html_url: string;
    git_url: string;
    download_url: string | null;
    type: 'file' | 'dir';
}
```

### Config Types (`config.ts`)

```typescript
// Category and Vertical types are derived from the config object
type Category = typeof config.categories[number];
// → { id: string; name: string; displayName: string }

type Vertical = typeof config.verticals[number];
// → { id: string; displayName: string }
```

---

## 11. Configuration & Environment

### Central Config (`src/config.ts`)

All platform configuration lives in a single typed object:

```typescript
export const config = {
  // Content source — defaults to public repo, overridable for internal repos
  githubRepo: import.meta.env.VITE_GITHUB_REPO || 'ROCm/rocm-blogs',
  githubBranch: import.meta.env.VITE_GITHUB_BRANCH || 'release',

  // Blog taxonomy
  blogsPath: 'blogs',
  categories: [
    { id: 'artificial-intelligence', name: 'Applications & Models', displayName: 'Applications & Models' },
    { id: 'ecosystems-and-partners', name: 'Ecosystems & Partners', displayName: 'Ecosystems & Partners' },
    { id: 'high-performance-computing', name: 'HPC', displayName: 'High Performance Computing' },
    { id: 'software-tools-optimization', name: 'Software Tools & Optimizations', displayName: 'Software Tools & Optimizations' }
  ],
  verticals: [
    { id: 'AI', displayName: 'AI' },
    { id: 'HPC', displayName: 'HPC' },
    { id: 'Data Science', displayName: 'Data Science' },
    { id: 'Systems', displayName: 'Systems' },
    { id: 'Developers', displayName: 'Developers' }
  ],

  // Featured posts reference file
  featuredBlogsCsv: 'blogs/featured-blogs.csv',
  postsPerPage: 12,

  // Content mode toggle
  useLocalContent: import.meta.env.VITE_USE_LOCAL_CONTENT === 'true',

  // API endpoints
  githubApiBase: 'https://api.github.com',
  githubRawBase: 'https://raw.githubusercontent.com'
};
```

### Dual Content Mode

The platform supports two content sources:

| Mode | When | How |
|---|---|---|
| **GitHub API** | Default in dev + production | Fetches from `raw.githubusercontent.com/{repo}/{branch}/blogs/...` |
| **Local/Bundled** | CI builds, `VITE_USE_LOCAL_CONTENT=true` | Reads from bundled `public/blogs-index.json` + `public/blogs-content/` |

The service layer (`services/github.ts` and `services/local.ts`) abstracts this — components don't know or care where content comes from.

---

## 12. Styling Architecture

### Layer Stack

```
1. index.css          — CSS custom properties (theme tokens), global resets
2. Tailwind CSS 4     — Utility classes via @tailwindcss/vite plugin
3. Component CSS      — Co-located .css files per component (BlogCard.css, etc.)
4. myst-content.css   — 53 KB of styles for MyST-rendered content
```

### Theme System

The platform supports 3 themes via `data-theme` and `data-theme-variant` attributes on `<html>`:

```css
/* index.css — CSS custom properties */
:root[data-theme="light"] {
  --bg-primary: #ffffff;
  --text-primary: #1a1a2e;
  --accent: #ed1c24;
  /* ... */
}

:root[data-theme="dark"] {
  --bg-primary: #0f0f23;
  --text-primary: #e4e4e7;
  --accent: #ed1c24;
  /* ... */
}
```

Theme is persisted to `localStorage` and applied before React renders (in `main.tsx`) to prevent flash of unstyled content (FOUC):

```typescript
// main.tsx — runs before createRoot()
const savedTheme = localStorage.getItem('theme') || 'dark'
document.documentElement.setAttribute('data-theme', savedTheme)
```

### Tailwind CSS 4

The platform uses Tailwind CSS 4 with the Vite plugin for zero-configuration setup:

```typescript
// vite.config.ts
plugins: [react(), tailwindcss(), serveBlogsPlugin()]
```

Tailwind utilities are used alongside custom CSS — the `tailwind-merge` library resolves conflicts:

```typescript
// lib/utils.ts
import { clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs) {
  return twMerge(clsx(inputs))
}
```

### MyST Content Styles (`myst-content.css`)

At 53 KB, this is the largest CSS file. It provides styles for every MyST-rendered element:
- Admonition boxes (note, warning, tip, danger, etc.)
- Code blocks with language tabs
- Math equations (KaTeX)
- Tables (responsive, striped)
- Grid and card layouts
- Figure captions
- Glossary terms
- Theorem/proof blocks
- Terminal widgets
- Benchmark tables
- Comparison panels

---

## 13. Performance Architecture

### Startup Optimization

```
main.tsx load order:
  1. Buffer polyfill (synchronous — required for gray-matter)
  2. Theme application (synchronous — prevents FOUC)
  3. createRoot() + <App /> render
  4. Firebase init (deferred via requestIdleCallback, timeout 2000ms)
  5. Cache warming (deferred via requestIdleCallback, timeout 1200ms)
```

Firebase and navigation caches are initialized **after the first paint** using `requestIdleCallback`. This prevents the Firebase SDK (~200 KB) from blocking initial rendering.

### Code Splitting

Every page is lazy-loaded:

```typescript
const HomePage = lazy(() => import('./pages/HomePage'))
const BlogPage = lazy(() => import('./pages/BlogPage'))
const SearchResultsPage = lazy(() => import('./pages/SearchResultsPage'))
```

The initial bundle contains only:
- React runtime
- Router
- Header + Footer
- Loading spinner CSS

Page-specific code downloads on navigation.

### Vendor Chunk Splitting

```typescript
manualChunks: {
  'vendor-react': ['react', 'react-dom', 'react-router-dom'],
  'vendor-utils': ['date-fns', 'gray-matter', 'minisearch'],
}
```

Vendor chunks are cached independently. Updating application code doesn't invalidate the vendor cache.

### Content Prefetching

```typescript
// utils/blogPrefetch.ts
export function warmNavigationCaches() {
  // Prefetch the blog index and search index during idle time
}
```

A Web Worker (`workers/prefetch.worker.ts`) runs in the background to:
- Pre-fetch blog metadata
- Warm the search index
- Pre-load thumbnails for visible cards

### Pre-rendered Content

Blog content is pre-rendered to HTML at build time. Loading a blog post:

```
Without pre-rendering:        With pre-rendering:
  1. Fetch README.md             1. Fetch category--slug.json
  2. Parse frontmatter           2. Insert HTML into DOM
  3. Process MyST syntax         ← done (~50ms)
  4. Render markdown → HTML
  5. Insert into DOM
  (~500-2000ms)
```

---

## 14. Testing

### Framework

- **Vitest** (v4.0.18) — Vite-native test runner
- Compatible with Jest API (`describe`, `it`, `expect`)
- Uses the same Vite config for module resolution

### Test Suite (`myst-parser.test.ts`)

The MyST parser has **19 test cases** across 5 test groups:

```
MyST Parser - escapeHtml
  ✓ escapes HTML special characters
  ✓ escapes ampersands

MyST Parser - parseMystMath
  ✓ parses inline math $...$
  ✓ parses display math $$...$$
  ✓ parses {math}`...` role

MyST Parser - collectMystTargets
  ✓ collects target definitions
  ✓ converts GitHub blob URLs to raw URLs

MyST Parser - parseMystDirectives
  ✓ parses note admonition
  ✓ parses warning admonition
  ✓ parses dropdown directive
  ✓ parses glossary directive
  ✓ parses prf:theorem directive
  ✓ parses grid and card directives
  ✓ parses exercise and solution directives
  ✓ parses mermaid directive
  ✓ parses terminal directive
  ✓ parses terminal directive with custom title and prompt
  ✓ parses benchmark directive
  ✓ parses comparison directive

MyST Parser - parseMystRoles
  ✓ parses {button} role
  ✓ parses {term} role
  ✓ parses {sub} and {sup} roles
  ✓ parses {kbd} role
  ✓ parses {abbr} role with title

MyST Parser - processAbbreviations
  ✓ replaces abbreviations with abbr tags
  ✓ handles word boundaries correctly
```

### Running Tests

```bash
# Run once
npm run test

# Watch mode (re-runs on file changes)
npm run test:watch
```

---

## 15. CI/CD Pipeline

### GitHub Actions (`ci.yml`)

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main, master]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - Checkout repository (full history for changed-file detection)
      - Setup Node.js 20 with npm cache
      - Install dependencies (npm ci — exact lockfile)
      - Clone ROCm blogs data (git clone --depth 1)
      - ESLint (only changed .ts/.tsx/.js/.jsx files)
      - Prettier check (only changed files)
      - Run tests (npm run test)
      - Production build (npm run build — full pipeline)
```

### Key CI Design Decisions

1. **Incremental linting**: Only changed files are linted/formatted, not the entire codebase. This keeps CI fast even as the project grows.
2. **Blog data cloned in CI**: The `rocm-blogs` repo is shallow-cloned so the build scripts can generate the index and pre-render content.
3. **Full production build**: Every PR runs the complete build pipeline to catch build-time errors (broken imports, type errors, missing assets).

### Quality Gates

| Gate | Tool | Fails on |
|---|---|---|
| Type safety | `tsc -b` | Any TypeScript error |
| Linting | ESLint `--max-warnings=0` | Any lint warning or error |
| Formatting | Prettier `--check` | Any formatting difference |
| Tests | Vitest | Any failing test |
| Build | Vite | Bundle errors, missing imports |

### Git Hooks (Husky + lint-staged)

Pre-commit hooks run automatically:

```json
"lint-staged": {
  "*.{js,jsx,ts,tsx}": ["prettier --write", "eslint --fix --max-warnings=0"],
  "*.{css,md,json,yml,yaml}": ["prettier --write"]
}
```

### Conventional Commits

The project enforces conventional commit format via Commitizen + commitlint:

```bash
npm run commit  # Interactive prompt
# → feat(search): add synonym expansion for GPU terms
# → fix(parser): handle nested code blocks in dropdowns
```

### CalVer Releases

Version numbers follow Calendar Versioning (`YYYY.M.DD-r.N`):

```bash
npm run release:calver  # → 2026.2.11-r.1
```

---

## 16. Deployment

### Firebase Hosting

The platform deploys to Firebase Hosting:

```json
{
  "hosting": {
    "public": "dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [{ "source": "**", "destination": "/index.html" }]
  }
}
```

- **`public: "dist"`** — Serves the Vite build output
- **SPA rewrite** — All routes return `index.html`, React Router handles routing client-side
- **Static assets** — Blog images, JSON indices, and JS bundles are served directly from the CDN

### Deployment Flow

```
Developer pushes to main
  → GitHub Actions CI runs (lint + test + build)
  → On success, Firebase CLI deploys dist/ to hosting
  → Firebase CDN propagates worldwide
  → Users get the latest version on next page load
```

---

## 17. Developer Workflow

### Adding a New Blog Post

No platform changes needed. Blog content lives in the separate `rocm-blogs` repo:

1. Create `blogs/{category}/{slug}/README.md` with MyST frontmatter
2. Add thumbnail image to `blogs/{category}/{slug}/images/`
3. Commit and push to `rocm-blogs`
4. The platform picks it up automatically (GitHub API mode) or on next rebuild (bundled mode)

### Adding a New Component

```bash
# 1. Create component files
touch src/components/MyWidget.tsx src/components/MyWidget.css

# 2. Write the component
# 3. Import it where needed
# 4. Run tests
npm run test

# 5. Commit
npm run commit
```

### Adding a New Page

1. Create `src/pages/MyPage.tsx` and `src/pages/MyPage.css`
2. Add a lazy import in `App.tsx`:
   ```tsx
   const MyPage = lazy(() => import('./pages/MyPage').then(m => ({ default: m.MyPage })))
   ```
3. Add a route:
   ```tsx
   <Route path="/my-page" element={<MyPage />} />
   ```

### Adding a New MyST Directive

1. Add a case to `generateDirectiveHtml()` in `src/utils/myst-parser.ts`
2. Add styles to `src/styles/myst-content.css`
3. Add a test case to `src/utils/myst-parser.test.ts`
4. Run `npm run test` to verify

---

## 18. Comparison: React vs Sphinx

| Dimension | Sphinx (rocm-blogs-sphinx) | React (program-repo) |
|---|---|---|
| **Language** | Python 3.10 | TypeScript 5.9 |
| **Framework** | Docutils + Sphinx | React 18 + Vite 7 |
| **Build tool** | Make + Python setuptools | Vite (esbuild + Rollup) |
| **Styling** | Raw CSS in Python strings | Tailwind CSS 4 + co-located CSS |
| **Dev server startup** | 7+ minutes (full rebuild) | <2 seconds (Vite HMR) |
| **Hot reload** | None (full rebuild required) | Sub-second (React Fast Refresh) |
| **Content format** | reStructuredText | MyST Markdown (CommonMark superset) |
| **Component model** | None (raw HTML strings) | React components with typed props |
| **Client-side search** | None (static HTML) | MiniSearch with stemming + synonyms |
| **Code splitting** | None (all HTML pre-generated) | Route-based lazy loading |
| **Type safety** | None (Python string templates) | Full TypeScript coverage |
| **Testing** | No test suite | Vitest with 19+ test cases |
| **CI pipeline** | None | GitHub Actions (lint + format + test + build) |
| **Codebase size** | 12,500+ lines across 9 files | Modular, ~150 files |
| **God file** | `__init__.py` (4,667 lines) | Largest file: `BlogPost.tsx` (861 lines) |
| **Global state** | 15+ mutable globals | None (React state + props) |

### Build Time Comparison

```
Sphinx (rocm-blogs-sphinx):
  Cold build:  7 min 23 sec
  Warm build:  4 min 12 sec
  Dev rebuild: 4 min 12 sec (no incremental mode)

React (program-repo):
  Cold build:  ~45 sec (index + prerender + tsc + vite)
  Warm build:  ~20 sec (cached deps)
  Dev rebuild: <100 ms (HMR, single file)
```

### Developer Productivity

```
Task: "Change the blog card's date format from 'Jan 15, 2026' to '2026-01-15'"

Sphinx:
  1. Find generate_grid() in grid.py (line 59, 570-line function)
  2. Find the date formatting line
  3. Change Python strftime format
  4. Rebuild (4+ minutes)
  5. Manually check the HTML output
  6. No tests to verify

React:
  1. Open BlogCard.tsx (83 lines)
  2. Change the date-fns format string
  3. Save → HMR updates in <1 second
  4. Tests verify the change passes
```

---

*This document reflects the state of the platform as of version `2026.2.11-r.1`.*
