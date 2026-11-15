// The whole site script: theme, language, API-style preference, the contents
// drawer, copy buttons and the "on this page" marker. No dependencies.

(() => {
  const root = document.documentElement;
  const store = {
    get(k, fallback) {
      try {
        return localStorage.getItem(k) || fallback;
      } catch {
        return fallback;
      }
    },
    set(k, v) {
      try {
        localStorage.setItem(k, v);
      } catch {
        /* a reader with storage disabled keeps the choice for this page only */
      }
    },
  };

  // ---------- language ----------

  const languages = ["en", "zh"];
  const browser = (navigator.language || "en").toLowerCase();
  let lang = store.get("moonhelo.lang", "");
  if (!languages.includes(lang)) lang = browser.startsWith("zh") ? "zh" : "en";

  const applyLang = (next) => {
    root.dataset.lang = next;
    root.lang = next === "zh" ? "zh-CN" : "en-US";
    for (const b of document.querySelectorAll("[data-set-lang]")) {
      b.setAttribute("aria-pressed", String(b.dataset.setLang === next));
    }
  };
  applyLang(lang);

  for (const b of document.querySelectorAll("[data-set-lang]")) {
    b.addEventListener("click", () => {
      lang = b.dataset.setLang;
      store.set("moonhelo.lang", lang);
      applyLang(lang);
    });
  }

  // ---------- theme ----------

  const theme = store.get("moonhelo.theme", "");
  if (theme === "light" || theme === "dark") root.dataset.theme = theme;

  const toggle = document.querySelector("[data-theme-toggle]");
  if (toggle) {
    toggle.addEventListener("click", () => {
      const now =
        root.dataset.theme ||
        (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
      const next = now === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      store.set("moonhelo.theme", next);
    });
  }

  // ---------- API style: the same sample in three shapes ----------

  const styles = ["function", "class", "annotation"];
  let style = store.get("moonhelo.style", "function");
  if (!styles.includes(style)) style = "function";

  const applyStyle = (next) => {
    for (const block of document.querySelectorAll("[data-code]")) {
      const panes = [...block.querySelectorAll(".pane")];
      if (!panes.length) continue;
      const has = panes.some((p) => p.dataset.style === next);
      const chosen = has ? next : panes[0].dataset.style;
      for (const pane of panes) pane.hidden = pane.dataset.style !== chosen;
      for (const tab of block.querySelectorAll("[data-style]")) {
        tab.setAttribute("aria-selected", String(tab.dataset.style === chosen));
      }
    }
  };
  applyStyle(style);

  for (const tab of document.querySelectorAll("[data-style]")) {
    tab.addEventListener("click", () => {
      style = tab.dataset.style;
      store.set("moonhelo.style", style);
      applyStyle(style);
    });
  }

  // ---------- the page scrollbar hides its thumb while at the top ----------

  const atTop = () => root.classList.toggle("at-top", scrollY <= 4);
  addEventListener("scroll", atTop, { passive: true });
  atTop();

  // ---------- contents drawer ----------

  const menu = document.querySelector("[data-menu]");
  if (menu) {
    menu.addEventListener("click", () => {
      const open = document.body.dataset.menu === "open";
      document.body.dataset.menu = open ? "" : "open";
      menu.setAttribute("aria-expanded", String(!open));
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        document.body.dataset.menu = "";
        menu.setAttribute("aria-expanded", "false");
      }
    });
  }

  // ---------- which heading the reader is in ----------

  const links = [...document.querySelectorAll(".toc a")];
  if (links.length) {
    const heads = links
      .map((a) => document.getElementById(a.getAttribute("href").slice(1)))
      .filter(Boolean);
    const seen = new Set();
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) seen.add(e.target.id);
          else seen.delete(e.target.id);
        }
        const active = heads.find((h) => seen.has(h.id));
        for (const a of links) {
          a.classList.toggle(
            "on",
            !!active && a.getAttribute("href") === "#" + active.id
          );
        }
      },
      { rootMargin: "-10% 0px -75% 0px" }
    );
    heads.forEach((h) => io.observe(h));
  }

  // ---------- copy ----------

  for (const btn of document.querySelectorAll("[data-copy]")) {
    btn.addEventListener("click", async () => {
      const block = btn.closest("[data-code]");
      const pre = block?.querySelector(".pane:not([hidden]) pre, pre");
      if (!pre) return;
      const text = pre.innerText.replace(/^\$ /gm, "");
      try {
        await navigator.clipboard.writeText(text);
        const label = btn.textContent;
        btn.textContent = "copied";
        setTimeout(() => (btn.textContent = label), 1400);
      } catch {
        btn.textContent = "select";
      }
    });
  }
})();
