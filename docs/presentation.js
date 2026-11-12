const measureButtons = [...document.querySelectorAll("[data-measure]")];
const periods = [...document.querySelectorAll(".comparison-period")];
const measureTitle = document.getElementById("training-measure");
const comparisonNote = document.getElementById("training-note");

const measures = {
  minutes: {
    title: "Workout minutes",
    unit: "min",
    values: [[140.8, 80.4], [121.2, 25.4]],
    note: "The latest block was 74.6 minutes shorter.",
  },
  sessions: {
    title: "Workout sessions",
    unit: "sessions",
    values: [[3, 2], [3, 1]],
    note: "Both blocks included three runs. The latest had one fewer strength session.",
  },
};

for (const button of measureButtons) {
  button.addEventListener("click", () => {
    const key = button.dataset.measure;
    const measure = measures[key];
    const max = Math.max(...measure.values.map(([running, strength]) => running + strength));
    for (const option of measureButtons) option.setAttribute("aria-pressed", String(option === button));
    measureTitle.textContent = measure.title;
    comparisonNote.textContent = measure.note;
    for (const [index, period] of periods.entries()) {
      const [running, strength] = measure.values[index];
      const track = period.querySelector(".comparison-track");
      track.setAttribute("aria-label", key === "minutes"
        ? running + " minutes running and " + strength + " minutes strength training"
        : running + " running sessions and " + strength + " strength training " + (strength === 1 ? "session" : "sessions"));
      track.children[0].style.setProperty("--length", running / max * 100 + "%");
      track.children[1].style.setProperty("--length", strength / max * 100 + "%");
      const total = running + strength;
      period.querySelector("[data-total]").textContent = (key === "minutes" ? total.toFixed(1) : total) + " " + measure.unit;
    }
  });
}
document.querySelector(".measure-switch").hidden = false;

function openManualAnchor() {
  if (/^#(?:\d{2}-|ref-|references$|evidence$|navigation$)/.test(location.hash)) {
    location.replace("manual.html" + location.hash);
  }
}
window.addEventListener("hashchange", openManualAnchor);
openManualAnchor();
