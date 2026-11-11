const device = document.getElementById("story-device");
const screen = document.getElementById("story-screen");
const imageLink = document.getElementById("story-image-link");
const chapterLinks = [...document.querySelectorAll(".chapter-links a")];
const scenes = [...document.querySelectorAll(".story-scene")].map(element => ({
  trigger: element.previousElementSibling.matches(".chapter-intro") ? element.previousElementSibling : element,
  chapter: element.closest(".story-chapter").id,
  image: element.querySelector(".scene-image"),
}));
const mobile = matchMedia("(max-width: 700px)");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
let current = -1;
let scheduled = false;
let reveal;

function showScene(index) {
  if (index === current) return;
  current = index;
  const scene = scenes[index];
  const source = scene.image.getAttribute("src");
  device.dataset.chapter = scene.chapter;
  imageLink.href = source;
  screen.alt = scene.image.alt;
  if (screen.getAttribute("src") !== source) screen.src = source;
  for (const link of chapterLinks) {
    if (link.hash !== "#" + scene.chapter) {
      link.removeAttribute("aria-current");
      continue;
    }
    link.setAttribute("aria-current", "location");
    if (mobile.matches) {
      const rail = link.parentElement;
      const item = link.getBoundingClientRect();
      const bounds = rail.getBoundingClientRect();
      if (item.left < bounds.left || item.right > bounds.right) {
        rail.scrollLeft += (item.left + item.right - bounds.left - bounds.right) / 2;
      }
    }
  }
}

function updateScene() {
  scheduled = false;
  const guide = mobile.matches
    ? Math.min(innerHeight - 40, device.getBoundingClientRect().bottom + 100)
    : innerHeight * .53;
  let index = 0;
  for (const [position, scene] of scenes.entries()) {
    if (scene.trigger.getBoundingClientRect().top > guide) break;
    index = position;
  }
  showScene(index);
}

function scheduleUpdate() {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(updateScene);
}

screen.addEventListener("load", () => {
  reveal?.cancel();
  if (!reduceMotion.matches && screen.animate) {
    reveal = screen.animate([{ opacity: .38 }, { opacity: 1 }], { duration: 230, easing: "ease-out" });
  }
});
device.closest(".story-layout").classList.add("enhanced");
device.hidden = false;
window.addEventListener("scroll", scheduleUpdate, { passive: true });
window.addEventListener("resize", scheduleUpdate);
window.addEventListener("hashchange", scheduleUpdate);
scheduleUpdate();
