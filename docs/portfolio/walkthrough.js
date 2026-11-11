const tour = document.getElementById("tour");
const chapterList = document.getElementById("chapters");
const chapterSelect = document.getElementById("chapter-select");
const stepIndex = document.getElementById("step-index");
const chapterName = document.getElementById("current-chapter");
const stepCount = document.getElementById("step-count");
const progress = document.getElementById("progress");
const stepTitle = document.getElementById("step-title");
const stepAction = document.getElementById("step-action");
const stepContext = document.getElementById("step-context");
const screen = document.getElementById("screen");
const fullScreen = document.getElementById("full-screen");
const hotspot = document.getElementById("hotspot");
const stageCaption = document.getElementById("stage-caption");
const previous = document.getElementById("previous");
const next = document.getElementById("next");
const sleepChoice = document.getElementById("sleep-choice");
const announcement = document.getElementById("announcement");

const steps = walkthroughChapters.flatMap(chapter => chapter.steps.map(step => ({ ...step, chapter })));
const chapterLinks = new Map();
const stepLinks = new Map();
const stepById = new Map(steps.map((step, index) => [step.id, index]));
const firstInChapter = new Map(walkthroughChapters.map(chapter => [chapter.id, chapter.steps[0].id]));
const number = index => String(index + 1).padStart(2, "0");
let current = -1;

for (const chapter of walkthroughChapters) {
  const item = document.createElement("li");
  const link = document.createElement("a");
  link.href = "#" + chapter.id;
  const title = document.createElement("span");
  title.className = "chapter-title";
  title.textContent = chapter.title;
  const goal = document.createElement("span");
  goal.className = "chapter-goal";
  goal.textContent = chapter.goal;
  link.append(title, goal);
  item.append(link);
  chapterList.append(item);
  chapterLinks.set(chapter.id, link);
  chapterSelect.add(new Option(chapter.title, chapter.id));
}

for (const [index, step] of steps.entries()) {
  const item = document.createElement("li");
  const link = document.createElement("a");
  link.href = "#" + step.id;
  link.textContent = number(index) + " · " + step.title;
  item.append(link);
  stepIndex.append(item);
  stepLinks.set(step.id, link);
}

function resolve(hash) {
  const id = hash.slice(1);
  return stepById.get(firstInChapter.get(id) ?? id);
}

function showHotspot() {
  const marker = steps[current]?.hotspot;
  hotspot.hidden = !marker || !screen.complete || screen.naturalWidth === 0;
  if (hotspot.hidden) return;
  hotspot.style.setProperty("--x", marker.x + "%");
  hotspot.style.setProperty("--y", marker.y + "%");
  hotspot.setAttribute("aria-label", marker.label);
  hotspot.title = marker.label;
}

function render(index, focus = false) {
  if (index === current) return;
  const old = steps[current];
  const step = steps[index];
  current = index;
  tour.dataset.chapter = step.chapter.id;
  chapterLinks.get(old?.chapter.id)?.removeAttribute("aria-current");
  stepLinks.get(old?.id)?.removeAttribute("aria-current");
  chapterLinks.get(step.chapter.id).setAttribute("aria-current", "step");
  stepLinks.get(step.id).setAttribute("aria-current", "step");
  chapterSelect.value = step.chapter.id;
  chapterName.textContent = step.chapter.title;
  stepCount.textContent = number(index) + " / " + steps.length;
  progress.value = index + 1;
  stepTitle.textContent = step.title;
  stepAction.textContent = step.action;
  stepContext.textContent = step.context;
  const source = "screenshots/" + step.id + ".png";
  screen.alt = "Rhythm Log sample screen · " + step.title;
  if (screen.getAttribute("src") !== source) screen.src = source;
  fullScreen.href = source;
  stageCaption.textContent = step.hotspot ? "Tap the purple marker to continue" : "iPhone preview · Sample data";
  previous.disabled = index === 0;
  next.innerHTML = index === steps.length - 1 ? "Restart walkthrough" : 'Next step <span aria-hidden="true">→</span>';
  sleepChoice.hidden = !["18-recovery-no-sleep", "19-recovery-activity"].includes(step.id);
  showHotspot();
  if (focus) {
    stepTitle.focus({ preventScroll: true });
    const bounds = stepTitle.getBoundingClientRect();
    if (bounds.top < 0 || bounds.bottom > window.innerHeight) stepTitle.scrollIntoView({ block: "start" });
    announcement.textContent = "Step " + (index + 1) + " of " + steps.length;
  }
}

function go(index) {
  if (!steps[index] || index === current) return;
  history.pushState(null, "", "#" + steps[index].id);
  render(index, true);
}

tour.addEventListener("click", event => {
  const link = event.target.closest("a[href^='#']");
  if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  go(resolve(link.hash));
});
chapterSelect.addEventListener("change", () => go(stepById.get(firstInChapter.get(chapterSelect.value))));
previous.addEventListener("click", () => go(current - 1));
next.addEventListener("click", () => go((current + 1) % steps.length));
hotspot.addEventListener("click", () => go(stepById.get(steps[current].hotspot.target)));
screen.addEventListener("load", showHotspot);
screen.addEventListener("error", showHotspot);
window.addEventListener("hashchange", () => render(resolve(location.hash) ?? 0));
progress.max = steps.length;
render(resolve(location.hash) ?? 0);
