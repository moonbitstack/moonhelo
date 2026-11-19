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

  // ---------- language: a listbox this stylesheet draws ----------

  const languages = ["en", "zh"];
  const langMenu = document.querySelector("[data-lang-menu]");
  const langToggle = document.querySelector("[data-lang-toggle]");
  const langLabel = document.querySelector("[data-lang-current]");
  const langList = langMenu ? langMenu.querySelector(".lang__list") : null;
  const langOptions = langMenu ? [...langMenu.querySelectorAll("[data-lang-option]")] : [];
  let lang = store.get("moonhelo.lang", "en");
  if (!languages.includes(lang)) lang = "en";

  const applyLang = (next) => {
    root.dataset.lang = next;
    root.lang = next === "zh" ? "zh-CN" : "en-US";
    if (langLabel) langLabel.textContent = next;
    for (const option of langOptions) {
      option.setAttribute("aria-selected", String(option.dataset.langOption === next));
    }
  };
  applyLang(lang);

  if (langMenu) {
    const isOpen = () => langToggle.getAttribute("aria-expanded") === "true";

    const setOpen = (open, focusFirst) => {
      langToggle.setAttribute("aria-expanded", String(open));
      langList.hidden = !open;
      if (!open) return;
      const chosen =
        langOptions.find((o) => o.getAttribute("aria-selected") === "true") || langOptions[0];
      if (focusFirst) chosen.focus();
    };

    const choose = (option) => {
      lang = option.dataset.langOption;
      store.set("moonhelo.lang", lang);
      applyLang(lang);
      setOpen(false);
      langToggle.focus();
    };

    langToggle.addEventListener("click", (event) => {
      event.stopPropagation();
      setOpen(!isOpen(), true);
    });

    langToggle.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        setOpen(true, true);
      }
    });

    for (const option of langOptions) {
      option.addEventListener("click", () => choose(option));
      option.addEventListener("keydown", (event) => {
        const at = langOptions.indexOf(option);
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          event.preventDefault();
          const step = event.key === "ArrowDown" ? 1 : -1;
          const next = (at + step + langOptions.length) % langOptions.length;
          langOptions[next].focus();
        } else if (event.key === "Home" || event.key === "End") {
          event.preventDefault();
          langOptions[event.key === "Home" ? 0 : langOptions.length - 1].focus();
        } else if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          choose(option);
        } else if (event.key === "Escape") {
          event.preventDefault();
          setOpen(false);
          langToggle.focus();
        } else if (event.key === "Tab") {
          setOpen(false);
        }
      });
    }

    document.addEventListener("click", (event) => {
      if (isOpen() && !langMenu.contains(event.target)) setOpen(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && isOpen()) {
        setOpen(false);
        langToggle.focus();
      }
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

  // ---------- which chapters this reader has been through ----------

  const mark = document.querySelector("[data-read-count]");
  if (mark) {
    let read = [];
    try {
      read = JSON.parse(store.get("moonhelo.read", "[]"));
      if (!Array.isArray(read)) read = [];
    } catch {
      read = [];
    }
    const here = document.body.dataset.slug;
    if (here && !read.includes(here)) read.push(here);
    store.set("moonhelo.read", JSON.stringify(read));

    for (const li of document.querySelectorAll(".sidebar li[data-slug]")) {
      if (read.includes(li.dataset.slug)) li.classList.add("done");
    }
    const total = Number(mark.dataset.total || 0) || 1;
    mark.textContent = `${Math.min(read.length, total)} / ${total}`;
    const bar = document.querySelector("[data-read-bar]");
    if (bar) bar.style.width = `${Math.min(100, (read.length / total) * 100)}%`;
  }

  // ---------- API style: the same sample in three shapes ----------

  // the five spellings a library can offer, which is what the tabs render
  const styles = ["function", "type", "annotation", "config", "spec"];
  let style = store.get("moonhelo.style", "function");
  if (!styles.includes(style)) style = "function";

  // what each block shows when the chosen spelling is not one of its own: the
  // block's own default, not whichever pane happens to come first
  const fallbacks = new Map();
  for (const block of document.querySelectorAll("[data-code]")) {
    const chosen = block.querySelector('[data-style][aria-selected="true"]');
    if (chosen) fallbacks.set(block, chosen.dataset.style);
  }

  const applyStyle = (next) => {
    for (const block of document.querySelectorAll("[data-code]")) {
      const panes = [...block.querySelectorAll(".pane")];
      if (!panes.length) continue;
      const has = panes.some((p) => p.dataset.style === next);
      const chosen = has ? next : fallbacks.get(block) || panes[0].dataset.style;
      for (const pane of panes) pane.hidden = pane.dataset.style !== chosen;
      // only the tabs are options; the panes carry data-style too, and marking a
      // pane as selected is an aria-selected on something that is not in a tablist
      for (const tab of block.querySelectorAll('[role="tab"]')) {
        tab.setAttribute("aria-selected", String(tab.dataset.style === chosen));
      }
    }
    // the cover's picker sets the same preference, so it shows which one holds
    for (const pick of document.querySelectorAll("[data-style-pick]")) {
      pick.setAttribute("aria-pressed", String(pick.dataset.style === next));
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

  // ---------- a mixed checkbox ----------
  // `indeterminate` exists only as a property, so the elements page marks the box
  // and this sets it. The style is the stylesheet's, as for every other control.

  for (const box of document.querySelectorAll("[data-indeterminate]")) {
    box.indeterminate = true;
  }

  // ---------- the page scrollbar hides its thumb while at the top ----------

  const atTop = () => root.classList.toggle("at-top", scrollY <= 4);
  addEventListener("scroll", atTop, { passive: true });
  atTop();

  // ---------- contents drawer ----------

  const menu = document.querySelector("[data-menu]");
  if (menu) {
    const setOpen = (open) => {
      document.body.dataset.menu = open ? "open" : "";
      menu.setAttribute("aria-expanded", String(open));
    };
    const isOpen = () => document.body.dataset.menu === "open";
    menu.addEventListener("click", () => setOpen(!isOpen()));
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && isOpen()) {
        setOpen(false);
        menu.focus();
      }
    });
    // A tap anywhere outside the drawer closes it, the dimmed page included.
    document.addEventListener("click", (e) => {
      if (isOpen() && !e.target.closest(".sidebar, [data-menu]")) setOpen(false);
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
