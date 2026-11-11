const walkthroughChapters = [
  {
    "id": "start",
    "title": "Get started",
    "goal": "Set up Apple Health access",
    "steps": [
      {
        "id": "01-welcome",
        "title": "Start with what you track",
        "action": "On first launch, tap Connect Apple Health and choose the records you want to share.",
        "context": "Heart rate, workouts, and steps can power the daytime views. You can leave sleep access off and add it later in Settings.",
        "hotspot": {
          "x": 82,
          "y": 91,
          "target": "02-day-timeline",
          "label": "Continue with sample data"
        }
      }
    ]
  },
  {
    "id": "day",
    "title": "Read a day",
    "goal": "Follow a reading from the dial to its source",
    "steps": [
      {
        "id": "02-day-timeline",
        "title": "Read the day around the dial",
        "action": "Hold a point on the dial to inspect its hourly HRV estimate. The info button explains the daily score.",
        "context": "The 47% example compares this day with the person’s recent HRV history. The purple arc gives sleep context, and the dial leaves unobserved hours blank.",
        "hotspot": {
          "x": 87,
          "y": 33,
          "target": "03-score-guide",
          "label": "Open the HRV score guide"
        }
      },
      {
        "id": "03-score-guide",
        "title": "Understand the 47%",
        "action": "Open Understanding Pressure to see what the daily and overnight scores compare.",
        "context": "A 47% daily score means roughly 47% of eligible historical daily medians were higher. The number ranks the day within one person’s history."
      },
      {
        "id": "04-day-hrv",
        "title": "Find the readings behind the score",
        "action": "Scroll to Heart Readings. Tap a dot to inspect a sample or open 30-Day Trend beneath the chart.",
        "context": "The dot chart shows actual SDNN readings in milliseconds. The shaded band shows the daytime reference range and the lower bars summarize available readings by hour.",
        "hotspot": {
          "x": 25,
          "y": 96,
          "target": "05-hrv-history",
          "label": "Open the 30-day trend"
        }
      },
      {
        "id": "05-hrv-history",
        "title": "Zoom out to 30 days",
        "action": "Open the HRV history from the daily chart. Move across the plot to inspect earlier dates.",
        "context": "Daily medians make it easier to compare the current reading with the past month. Check the number of days with readings before interpreting the pattern."
      },
      {
        "id": "06-raw-readings",
        "title": "Check the source of a dot",
        "action": "Tap View All Readings beneath the chart to open its sample list.",
        "context": "Each row shows the time, value, and source. Use this view to check whether an unusual point came from a different source or time of day."
      },
      {
        "id": "07-day-steps",
        "title": "See when you moved",
        "action": "Scroll to Hourly Steps in the Day view.",
        "context": "The bars show when movement accumulated. In this example, one hour stands out even though the daily total alone would hide its timing."
      },
      {
        "id": "08-sleep-stages",
        "title": "Expand the sleep record",
        "action": "Under Sleep, open Sleep Details to inspect individual stage intervals.",
        "context": "The colored blocks show recorded stages. The expanded rows let you check each stage’s start and end times."
      },
      {
        "id": "09-day-workouts",
        "title": "Pick a workout to investigate",
        "action": "Scroll to Workouts and select Running.",
        "context": "The row previews start time, duration, and available active energy. The same workout detail is reachable from the weekly training list.",
        "hotspot": {
          "x": 52,
          "y": 81,
          "target": "10-workout-overview",
          "label": "Open the running workout"
        }
      }
    ]
  },
  {
    "id": "workouts",
    "title": "Open a workout",
    "goal": "Inspect a run from summary to samples",
    "steps": [
      {
        "id": "10-workout-overview",
        "title": "Get the outline of the run",
        "action": "Open a workout to see its duration, energy, and available heart-rate statistics. Scroll down for the zone breakdown.",
        "context": "This synthetic run lasted just over 35 minutes and averaged 145 BPM. The header identifies its place among runs that month."
      },
      {
        "id": "11-workout-zones",
        "title": "See where the time went",
        "action": "Look for the longest bar in Time in Zones and check its BPM boundaries.",
        "context": "Most of this run’s accounted-for time falls in Zones 3 and 4. Check the note under the bars to see whether the app used recorded times or estimated them from samples."
      },
      {
        "id": "12-workout-heart-rate",
        "title": "Follow heart rate during the run",
        "action": "Switch between Raw and Color-coded above the chart. Select a mark or open View All Readings to inspect the recorded samples.",
        "context": "The time axis shows how the session unfolded. The zone summary tells you how long the runner spent at each intensity."
      },
      {
        "id": "13-workout-calendar",
        "title": "Put one run in context",
        "action": "In This Month, tap a highlighted date to open that day’s workout list.",
        "context": "The calendar shows how often this activity appeared across the month. A highlight represents a recorded workout, regardless of its duration."
      }
    ]
  },
  {
    "id": "training",
    "title": "Compare training",
    "goal": "Go from a weekly change to the sessions behind it",
    "steps": [
      {
        "id": "14-week-training",
        "title": "Find what changed this week",
        "action": "Open Week → Training. Select a colored bar to see its seven-day block and workout count.",
        "context": "The sample week totals 147 minutes, down 75 from the preceding block. Strength training accounts for the largest drop.",
        "hotspot": {
          "x": 86,
          "y": 75,
          "target": "15-week-workouts",
          "label": "Expand the selected week’s workouts"
        }
      },
      {
        "id": "15-week-workouts",
        "title": "Check which sessions contributed",
        "action": "Expand the workout count beneath the bars. Tap a row to inspect the session itself.",
        "context": "The list connects each colored block with its recorded workouts. It helps you see whether fewer sessions or shorter sessions changed the total.",
        "hotspot": {
          "x": 53,
          "y": 81,
          "target": "10-workout-overview",
          "label": "Inspect the first run"
        }
      },
      {
        "id": "16-training-performance",
        "title": "Compare like-for-like workouts",
        "action": "Scroll to Training Performance. Pick an activity and setting, then compare points at nearby paces. Use the lower chart for one-minute heart-rate recovery.",
        "context": "The two charts answer different questions: heart rate during similar efforts, and how much it dropped after exercise. Consider route, weather, and cooldown when comparing sessions."
      },
      {
        "id": "17-training-calendar",
        "title": "See how workouts were spaced",
        "action": "In Month → Training, switch to the calendar and pick a date.",
        "context": "The calendar highlights workout days and shows total minutes for each. Use the spacing to see clusters and gaps in the month."
      }
    ]
  },
  {
    "id": "recovery",
    "title": "Explore recovery",
    "goal": "Start with daytime data, then explore overnight records",
    "steps": [
      {
        "id": "18-recovery-no-sleep",
        "title": "Start with daytime recovery",
        "action": "Open Month → Recovery. Select a date in the HRV plot to see its recorded activity context.",
        "context": "This sample profile has no sleep records. Daytime HRV still shows observed days, a seven-day median, and a personal reference range."
      },
      {
        "id": "19-recovery-activity",
        "title": "Put HRV beside activity",
        "action": "Scroll below HRV to Resting Heart Rate and Daily Steps. Compare each with the previous period.",
        "context": "The charts let you check whether resting heart rate or steps changed over the same period. Read the coverage counts before comparing medians."
      },
      {
        "id": "20-sleep-timing",
        "title": "Read a night by wake date",
        "action": "When sleep records exist, select a row in Sleep & Recovery to see its timing and available wake-day measurements.",
        "context": "A session can begin before midnight and end the next morning. The wake date keeps that session together in the weekly view."
      },
      {
        "id": "21-overnight-hrv",
        "title": "Switch to the overnight baseline",
        "action": "In the HRV Trend card, tap Overnight when that option is available.",
        "context": "Overnight and daytime HRV have separate reference histories. Read each series against its own past values and check how many nights contributed."
      },
      {
        "id": "22-overnight-vitals",
        "title": "Check sleeping heart and breathing rates",
        "action": "Expand Overnight Vitals and select a date to inspect the same night across metrics.",
        "context": "Each metric uses its own unit and recent range. The shared date axis helps you spot whether changes occurred together."
      },
      {
        "id": "23-oxygen-and-wrist-temperature",
        "title": "Read the last two overnight charts",
        "action": "Scroll to Blood Oxygen and Wrist Temperature. Look for the shaded ranges and any highlighted points.",
        "context": "A gap means there was no usable record for that metric. A highlighted point marks a difference from the sample profile’s recent range."
      }
    ]
  },
  {
    "id": "navigation",
    "title": "Navigate and personalize",
    "goal": "Jump across dates and adjust your settings",
    "steps": [
      {
        "id": "24-recovery-calendar",
        "title": "Find a day worth opening",
        "action": "Open Month → Recovery and switch to the calendar. Choose a metric from the menu, then tap a date.",
        "context": "The grid helps you locate a day with readings or a gap. Open the daily timeline to see the records behind that cell."
      },
      {
        "id": "25-year-trends",
        "title": "See the longer pattern",
        "action": "Switch to Year and scroll through heart rate, HRV, and resting heart rate.",
        "context": "Monthly averages give a broader view than the daily charts. Check sample coverage and context in a shorter view when a month stands out."
      },
      {
        "id": "26-date-picker",
        "title": "Jump straight to a date",
        "action": "Tap the date heading, choose a day in the picker, and tap Done.",
        "context": "Use Day, Week, Month, or Year to change the scale around that date. Today brings you back to the present."
      },
      {
        "id": "27-settings",
        "title": "Make the app yours",
        "action": "Tap the gear to change language or appearance, or revisit Apple Health access.",
        "context": "If a chart is empty, check whether the underlying record exists in Apple Health and whether Rhythm Log has permission to read it.",
        "hotspot": {
          "x": 55,
          "y": 59,
          "target": "28-manual-zones",
          "label": "Open manual heart-rate zones"
        }
      },
      {
        "id": "28-manual-zones",
        "title": "Enter your own zone boundaries",
        "action": "Open Manual Heart Rate Zones and enter four increasing BPM boundaries when your preferred HealthKit zones are unavailable.",
        "context": "The numbers in the demo are examples. The boundaries you enter determine how the app classifies eligible heart-rate readings."
      }
    ]
  }
];
