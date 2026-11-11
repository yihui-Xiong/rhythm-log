const chapterLinks = [...document.querySelectorAll(".chapter-links a")];
const chapters = chapterLinks.map(link => ({ link, section: document.getElementById(link.hash.slice(1)) }));
const mobile = matchMedia("(max-width: 700px)");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
const layouts = [...document.querySelectorAll(".story-layout")].map(layout => {
  const device = layout.querySelector("[data-story-device]");
  const screen = device.querySelector("[data-story-screen]");
  const scenes = [...layout.querySelectorAll(".story-scene")].map(element => ({
    trigger: element.previousElementSibling.matches(".chapter-intro") ? element.previousElementSibling : element,
    chapter: element.closest(".story-chapter").id,
    image: element.querySelector(".scene-image"),
  }));
  let animation;
  screen.addEventListener("load", () => {
    animation?.cancel();
    if (!reduceMotion.matches) {
      animation = screen.animate([{ opacity: .55, transform: "translateY(5px)" }, { opacity: 1, transform: "none" }], 230);
    }
  });
  layout.classList.add("enhanced");
  device.hidden = false;
  return { layout, device, screen, scenes, current: null };
});
let currentChapter;
let scheduled = false;

function updateChapter() {
  const active = chapters.findLast(({ section }) => section.getBoundingClientRect().top < innerHeight * .45);
  if (active === currentChapter) return;
  currentChapter?.link.removeAttribute("aria-current");
  currentChapter = active;
  if (!active) return;
  active.link.setAttribute("aria-current", "location");
  if (mobile.matches) {
    const rail = active.link.parentElement;
    const item = active.link.getBoundingClientRect();
    const bounds = rail.getBoundingClientRect();
    if (item.left < bounds.left || item.right > bounds.right) {
      rail.scrollLeft += (item.left + item.right - bounds.left - bounds.right) / 2;
    }
  }
}

function updateStory() {
  scheduled = false;
  updateChapter();
  for (const group of layouts) {
    const bounds = group.layout.getBoundingClientRect();
    if (bounds.bottom < 0 || bounds.top > innerHeight) continue;
    const guide = mobile.matches
      ? Math.min(innerHeight - 40, group.device.getBoundingClientRect().bottom + 100)
      : innerHeight * .53;
    const scene = group.scenes.findLast(item => item.trigger.getBoundingClientRect().top <= guide) ?? group.scenes[0];
    if (scene === group.current) continue;
    group.current = scene;
    group.device.dataset.chapter = scene.chapter;
    group.screen.alt = scene.image.alt;
    const source = scene.image.getAttribute("src");
    if (group.screen.getAttribute("src") !== source) group.screen.src = source;
  }
}

function scheduleUpdate() {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(updateStory);
}

function selectScreen(panel, id, animate = true) {
  for (const option of panel.querySelectorAll("[data-screen]")) {
    option.setAttribute("aria-pressed", String(option.dataset.screen === id));
  }
  for (const scene of panel.querySelectorAll(".story-scene")) {
    scene.hidden = scene.id !== id;
    if (!scene.hidden && animate && !reduceMotion.matches) {
      scene.animate([{ opacity: .35, transform: "translateY(7px)" }, { opacity: 1, transform: "none" }], 240);
    }
  }
}

const training = document.getElementById("training");
const recovery = document.getElementById("recovery");
const profiles = [...recovery.querySelectorAll("[data-profile]")];
const recoveryPanels = [...recovery.querySelectorAll("[data-recovery-panel]")];
const recoveryFigures = [...recovery.querySelectorAll("[data-recovery-figure]")];

function showProfile(profile, animate = true) {
  for (const option of profiles) option.setAttribute("aria-pressed", String(option.dataset.profile === profile));
  for (const panel of recoveryPanels) panel.hidden = panel.dataset.recoveryPanel !== profile;
  for (const figure of recoveryFigures) {
    figure.hidden = figure.dataset.recoveryFigure !== profile;
    if (!figure.hidden && animate && !reduceMotion.matches) {
      figure.animate([{ opacity: .45, transform: "translateY(7px)" }, { opacity: 1, transform: "none" }], 250);
    }
  }
  scheduleUpdate();
}

for (const control of document.querySelectorAll("[data-controls]")) control.hidden = false;
for (const panel of [training, ...recoveryPanels]) {
  const buttons = [...panel.querySelectorAll("[data-screen]")];
  selectScreen(panel, buttons[0].dataset.screen, false);
  for (const button of buttons) {
    button.addEventListener("click", () => {
      selectScreen(panel, button.dataset.screen);
      scheduleUpdate();
    });
  }
}
for (const button of profiles) {
  button.addEventListener("click", () => showProfile(button.dataset.profile));
}
showProfile("day", false);

const weekButtons = [...training.querySelectorAll("[data-week]")];
const weekDelta = document.getElementById("week-delta");
const weekNote = document.getElementById("week-note");
for (const button of weekButtons) {
  button.addEventListener("click", () => {
    const latest = button.dataset.week === "latest";
    for (const option of weekButtons) option.setAttribute("aria-pressed", String(option === button));
    weekDelta.textContent = latest ? "−75 min" : "+75 min";
    weekNote.textContent = latest
      ? "Compared with the previous block. Strength training accounts for the largest change."
      : "Compared with the following block. This earlier week recorded 222 minutes.";
  });
}

function revealLinkedScreen() {
  const target = document.getElementById(location.hash.slice(1));
  if (!target) return;
  const profilePanel = target.closest("[data-recovery-panel]");
  if (profilePanel) {
    showProfile(profilePanel.dataset.recoveryPanel, false);
    selectScreen(profilePanel, target.id, false);
  } else if (target.matches(".story-scene") && target.closest("#training")) {
    selectScreen(training, target.id, false);
  } else {
    return;
  }
  target.scrollIntoView({ block: "start" });
}

if ("IntersectionObserver" in window && !reduceMotion.matches) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("revealed");
      observer.unobserve(entry.target);
    }
  }, { threshold: .12 });
  for (const item of document.querySelectorAll("[data-reveal]")) {
    item.classList.add("reveal-ready");
    observer.observe(item);
  }
}

window.addEventListener("scroll", scheduleUpdate, { passive: true });
window.addEventListener("resize", scheduleUpdate);
window.addEventListener("hashchange", () => {
  revealLinkedScreen();
  scheduleUpdate();
});
revealLinkedScreen();
scheduleUpdate();

function revealEvidenceLink() {
  const target = document.getElementById(location.hash.slice(1));
  const details = target?.closest(".evidence-details");
  if (!details || details.open) return;
  details.open = true;
  target.scrollIntoView({ block: "start" });
}
window.addEventListener("hashchange", revealEvidenceLink);
revealEvidenceLink();

const initialHash = location.hash;
window.addEventListener("load", () => {
  if (!initialHash || location.hash !== initialHash) return;
  const target = document.getElementById(initialHash.slice(1));
  if (target && target.getBoundingClientRect().top > innerHeight) {
    target.scrollIntoView({ block: "start" });
  }
}, { once: true });
