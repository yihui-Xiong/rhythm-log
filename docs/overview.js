const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const weeks = [...document.querySelectorAll("[data-week]")];
const weekNote = document.getElementById("week-note");

function reveal(element) {
  if (!reducedMotion.matches) {
    element.animate([{ opacity: .5, transform: "translateY(4px)" }, { opacity: 1, transform: "none" }], {
      duration: 210, easing: "ease-out",
    });
  }
}

for (const button of weeks) {
  button.addEventListener("click", () => {
    for (const week of weeks) week.setAttribute("aria-pressed", String(week === button));
    const latest = button.dataset.week === "latest";
    const value = document.createElement("strong");
    value.textContent = latest ? "74.6 min less" : "221.2 min";
    const description = latest
      ? " than the previous block. Strength training accounts for most of the change."
      : " across five workouts. The following block contains four.";
    weekNote.replaceChildren(value, description);
    reveal(weekNote);
  });
}

const profiles = [...document.querySelectorAll("[data-profile]")];
const figures = [...document.querySelectorAll("[data-recovery]")];
document.querySelector(".profile-picker").hidden = false;
figures[1].hidden = true;
for (const button of profiles) {
  button.addEventListener("click", () => {
    for (const profile of profiles) profile.setAttribute("aria-pressed", String(profile === button));
    for (const figure of figures) {
      figure.hidden = figure.dataset.recovery !== button.dataset.profile;
      if (!figure.hidden) reveal(figure);
    }
  });
}

function openLegacyAnchor() {
  if (/^#(?:\d{2}-|ref-|references$|evidence$|navigation$)/.test(location.hash)) {
    location.replace("manual.html" + location.hash);
  }
}
window.addEventListener("hashchange", openLegacyAnchor);
openLegacyAnchor();
