const sharedOpening = (scriptLabel, appName) => [
  {
    title: `Write the ${scriptLabel} script`,
    body: `Keep each line short enough to read near the lens, then save the script in CueCard so it is ready for another take.`,
  },
  {
    title: `Set a comfortable pace`,
    body: `Choose the scroll speed and text size in CueCard, then rehearse the opening once before you record.`,
  },
  {
    title: `Float CueCard over ${appName}`,
    body: `Tap the green play button, then Start Overlay. CueCard shrinks into a movable window while ${appName} stays open.`,
  },
];

const appSteps = {
  "mobile/instagram": [
    ...sharedOpening("Instagram Reel", "Instagram"),
    {
      title: "Open the Instagram Reel camera",
      body: "In Instagram, tap Create, choose Reel, and switch to the selfie camera before starting the clip.",
    },
    {
      title: "Keep the record button clear",
      body: "Place CueCard just below the front camera without covering Instagram’s record or camera-switch controls.",
    },
    {
      title: "Record and review the Reel",
      body: "Film a short test, check your eye-line and pace, then adjust CueCard before recording the final Reel.",
    },
  ],
  "mobile/tiktok": [
    ...sharedOpening("TikTok", "TikTok"),
    {
      title: "Open the TikTok camera",
      body: "In TikTok, tap Add post (+), choose video, and switch to the selfie camera before recording.",
    },
    {
      title: "Fit the script around TikTok",
      body: "Move CueCard close to the lens while leaving TikTok’s record button and side controls uncovered.",
    },
    {
      title: "Record and review the TikTok",
      body: "Make a short test clip, check that your eyes stay near the lens, then adjust the speed for the final take.",
    },
  ],
  "mobile/youtube": [
    ...sharedOpening("YouTube video", "YouTube"),
    {
      title: "Open the YouTube Shorts camera",
      body: "In YouTube, tap Create and choose Short, or open the iPhone Camera app if you want a reusable video file.",
    },
    {
      title: "Leave the YouTube controls visible",
      body: "Keep CueCard near the front camera and clear of the record button, timer, and camera-switch controls.",
    },
    {
      title: "Record and review the video",
      body: "Check one short take for eye movement and pacing before recording the full Short or YouTube video.",
    },
  ],
  "mobile/linkedin": [
    ...sharedOpening("LinkedIn update", "LinkedIn"),
    {
      title: "Open the iPhone Camera app",
      body: "Choose Video and frame a clean talking-head shot; you will attach the finished clip to LinkedIn afterward.",
    },
    {
      title: "Keep the frame professional",
      body: "Place CueCard close to the lens, keep the record controls clear, and leave a little space around your face.",
    },
    {
      title: "Review, then post to LinkedIn",
      body: "Watch the saved clip once for pace and eye-line, then attach the strongest take to your LinkedIn post.",
    },
  ],
  "mobile/facebook": [
    ...sharedOpening("Facebook Reel", "Facebook"),
    {
      title: "Open the Facebook Reel camera",
      body: "In Facebook, choose Create Reel and switch to the selfie camera, or record in Camera and upload afterward.",
    },
    {
      title: "Keep Facebook’s controls clear",
      body: "Move CueCard beside the lens without covering the record, camera-switch, or effect controls.",
    },
    {
      title: "Record and review the Reel",
      body: "Test a few lines first, correct the pace or window position, then record the Facebook Reel.",
    },
  ],
  "mobile/snapchat": [
    ...sharedOpening("Snap", "Snapchat"),
    {
      title: "Open the Snapchat camera",
      body: "Switch to Snapchat, choose the selfie camera, and keep the Camera button visible below the floating script.",
    },
    {
      title: "Place the script below the lens",
      body: "Move CueCard near the front camera without covering Snapchat’s Camera button or camera-switch control.",
    },
    {
      title: "Record and check the Snap",
      body: "Press and hold the Camera button, review the Snap, then adjust CueCard before posting to Stories or Spotlight.",
    },
  ],
  "mobile/twitter": [
    ...sharedOpening("video for X", "X"),
    {
      title: "Open the iPhone Camera app",
      body: "Choose Video and record one focused point as a reusable clip before opening X.",
    },
    {
      title: "Keep the words beside the lens",
      body: "Place CueCard close to the front camera and keep the Camera app’s record control uncovered.",
    },
    {
      title: "Review, then attach it in X",
      body: "Check the saved clip for pace and eye-line, then attach the best take to your post in X.",
    },
  ],
  "mobile/twitch": [
    ...sharedOpening("Twitch intro", "Twitch"),
    {
      title: "Open the Twitch stream setup",
      body: "Start a mobile camera broadcast in Twitch and arrange CueCard around the preview, chat, and stream controls.",
    },
    {
      title: "Keep the script near the camera",
      body: "Place CueCard beside the front lens so you can read the intro without looking down at chat.",
    },
    {
      title: "Rehearse before going live",
      body: "Practice the opening in Camera first, then start the Twitch broadcast when the pace feels natural.",
    },
  ],
};

const cameraSteps = (device = "iPhone") => [
  {
    title: "Write and save the script",
    body: "Paste or type the script in CueCard, keep the lines short, and save a named copy for the next take.",
  },
  {
    title: "Set the pace and text size",
    body: "Choose a scroll speed you can speak comfortably and text large enough to read beside the lens.",
  },
  {
    title: "Start the floating window",
    body: "Tap the green play button, then Start Overlay to turn CueCard into a movable window.",
  },
  {
    title: `Open the ${device} Camera app`,
    body: "Choose Video and the selfie camera, then frame the shot before you begin recording.",
  },
  {
    title: "Move CueCard near the lens",
    body: "Use a narrow window just below the front camera and leave the Camera controls uncovered.",
  },
  {
    title: "Record a short test",
    body: "Check your eye-line and pace, then adjust the window or scroll speed before the final take.",
  },
];

const ipadSteps = [
  {
    title: "Write and save the script",
    body: "Paste or type the script in CueCard and save a named copy before setting the iPad in place.",
  },
  {
    title: "Choose full screen or floating",
    body: "Use full screen beside a separate camera, or Start Overlay when recording in an app on the iPad.",
  },
  {
    title: "Set the reading distance",
    body: "Place the iPad beside the camera and choose a text size you can read from where you will speak.",
  },
  {
    title: "Set the pace and start delay",
    body: "Choose a comfortable scroll speed and add a short delay so you have time to face the lens.",
  },
  {
    title: "Rehearse from your mark",
    body: "Read the opening once from your actual position and slow the script if you find yourself rushing.",
  },
  {
    title: "Record a short test",
    body: "Check the footage for visible eye movement, then adjust the iPad position before the final take.",
  },
];

function forApp(app) {
  if (!app || !app.guide) return null;

  const steps = appSteps[app.slug]
    || (app.slug === "mobile/ipad" ? ipadSteps : cameraSteps("iPhone"));

  const intro = app.subject
    ? `Use CueCard with ${app.subject} in six short steps, from the saved script to the final take.`
    : app.guide.intro;

  return { ...app.guide, intro, steps };
}

function forRole(role) {
  if (!role || !role.guide) return null;
  const audience = (role.targetAudience || role.name).toLowerCase();
  const useCase = (role.useCases && role.useCases[0]) || "next video";
  return {
    ...role.guide,
    steps: [
      {
        title: `Shape the script for ${useCase}`,
        body: `Write the lines ${audience} need word-perfect, keep each one short, and save the script in CueCard.`,
      },
      {
        title: "Rehearse one short take",
        body: "Float CueCard beside the lens, record the opening, then adjust the pace before filming the full version.",
      },
    ],
  };
}

module.exports = { forApp, forRole };
