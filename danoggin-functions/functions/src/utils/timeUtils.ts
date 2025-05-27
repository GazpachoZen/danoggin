/**
 * Check if current time is within responder's active hours
 */
export function isWithinActiveHours(responderData: object): boolean {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const data = responderData as any;
  const activeHours = data.activeHours;
  if (!activeHours) {
    console.log("No active hours defined, assuming always active");
    return true;
  }

  const startHour = activeHours.startHour || "08:00";
  const endHour = activeHours.endHour || "20:00";

  try {
    // For simplicity, we'll use UTC comparison
    // In production, you'd want proper timezone conversion
    const now = new Date();
    const currentHour = now.getUTCHours();
    const currentMinute = now.getUTCMinutes();
    const currentTotalMinutes = currentHour * 60 + currentMinute;

    // Parse start and end hours
    const [startH, startM] = startHour.split(":").map(Number);
    const [endH, endM] = endHour.split(":").map(Number);
    const startTotalMinutes = startH * 60 + startM;
    const endTotalMinutes = endH * 60 + endM;

    // Check if current time is within active hours
    if (startTotalMinutes <= endTotalMinutes) {
      // Normal case (e.g., 08:00 to 20:00)
      return currentTotalMinutes >= startTotalMinutes &&
             currentTotalMinutes <= endTotalMinutes;
    } else {
      // Overnight case (e.g., 22:00 to 06:00)
      return currentTotalMinutes >= startTotalMinutes ||
             currentTotalMinutes <= endTotalMinutes;
    }
  } catch (error) {
    console.error("Error checking active hours:", error);
    return true; // Default to active if we can't determine
  }
}