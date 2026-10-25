// Sheep wrapper script — injected at document start, main frame only.
// Reports navigation paths and scroll *amounts* to native. Never reads or sends page content.
(function () {
  if (window.__sheepInstalled) { return; }
  window.__sheepInstalled = true;

  function post(msg) {
    try {
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sheep;
      if (h) { h.postMessage(msg); }
    } catch (e) {}
  }

  function currentPath() {
    return (window.location && window.location.pathname) || "/";
  }

  // MARK: Navigation — SPA history + popstate (+ a slow poll as a safety net).
  var lastPath = null;
  function reportNav() {
    var path = currentPath();
    if (path === lastPath) { return; }
    lastPath = path;
    post({ type: "nav", path: path });
  }

  function wrap(name) {
    var original = window.history && window.history[name];
    if (typeof original !== "function") { return; }
    window.history[name] = function () {
      var result = original.apply(this, arguments);
      try { reportNav(); } catch (e) {}
      return result;
    };
  }
  wrap("pushState");
  wrap("replaceState");
  window.addEventListener("popstate", reportNav);
  window.addEventListener("hashchange", reportNav);

  // MARK: Hiding CSS — one <style id="sheep-css">, re-inserted if the SPA removes it.
  var sheepCSS = "";
  function ensureStyle() {
    var doc = window.document;
    if (!doc) { return; }
    var el = doc.getElementById("sheep-css");
    if (!sheepCSS) {
      if (el && el.parentNode) { el.parentNode.removeChild(el); }
      return;
    }
    if (!el) {
      el = doc.createElement("style");
      el.id = "sheep-css";
      var parent = doc.head || doc.documentElement;
      if (!parent) { return; }
      parent.appendChild(el);
    }
    if (el.textContent !== sheepCSS) { el.textContent = sheepCSS; }
  }
  window.__sheepSetCSS = function (css) {
    sheepCSS = css || "";
    ensureStyle();
  };
  window.addEventListener("DOMContentLoaded", ensureStyle);

  // MARK: Scroll — distance + active seconds (a second counts only if the user scrolled in it).
  var px = 0;
  var activeSec = 0;
  var scrolledThisSecond = false;
  var lastTop = typeof WeakMap === "function" ? new WeakMap() : null;
  var lastWindowY = window.scrollY || 0;

  function onScroll(event) {
    var target = event && event.target;
    var delta = 0;
    var doc = window.document;
    if (!target || target === doc || target === window || (doc && (target === doc.documentElement || target === doc.body))) {
      var y = window.scrollY || 0;
      delta = Math.abs(y - lastWindowY);
      lastWindowY = y;
    } else if (lastTop && typeof target.scrollTop === "number") {
      var top = target.scrollTop;
      var prev = lastTop.has(target) ? lastTop.get(target) : top;
      delta = Math.abs(top - prev);
      lastTop.set(target, top);
    }
    if (delta > 0) {
      px += delta;
      scrolledThisSecond = true;
    }
  }
  // Capture so inner scroll containers (scroll events don't bubble) are counted too.
  window.addEventListener("scroll", onScroll, { passive: true, capture: true });

  var ticks = 0;
  setInterval(function () {
    if (scrolledThisSecond) {
      activeSec += 1;
      scrolledThisSecond = false;
    }
    ticks += 1;
    reportNav();
    ensureStyle();
    if (ticks % 5 === 0) {
      if (px > 0) {
        post({ type: "scroll", px: Math.round(px), activeSec: activeSec, path: currentPath() });
      }
      px = 0;
      activeSec = 0;
    }
  }, 1000);

  reportNav();
})();
