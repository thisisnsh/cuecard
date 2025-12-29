use serde::{Deserialize, Serialize};

/// Represents a segment of the teleprompter content
/// Each segment is separated by [time mm:ss] tags
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeleprompterSegment {
    /// The text content (with [note] tags preserved, [time] tags removed)
    pub text: String,
    /// Duration in seconds for this segment (None = use default speed)
    pub duration_seconds: Option<u32>,
    /// Cumulative start time in seconds from beginning
    pub start_time_seconds: u32,
}

/// Parsed content ready for teleprompter display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeleprompterContent {
    /// All segments parsed from the notes
    pub segments: Vec<TeleprompterSegment>,
    /// Total duration if all segments have timing, None otherwise
    pub total_duration_seconds: Option<u32>,
    /// Whether any segment has timing information
    pub has_timing: bool,
}

/// Parse notes content into teleprompter segments
///
/// # Format
/// - `[time mm:ss]` - Defines timing for the following section
/// - `[note content]` - Preserved for pink highlighting
///
/// # Example
/// ```text
/// Welcome! [time 00:30]
/// This scrolls in 30 seconds.
///
/// [time 01:00]
/// This scrolls in 1 minute.
/// [note remember to smile]
///
/// Conclusion.
/// ```
pub fn parse_notes_to_segments(notes: &str) -> TeleprompterContent {
    let time_pattern = regex::Regex::new(r"\[time\s+(\d{1,2}):(\d{2})\]").unwrap();

    let mut segments: Vec<TeleprompterSegment> = Vec::new();
    let mut cumulative_time: u32 = 0;
    let mut has_any_timing = false;

    // Split content by [time mm:ss] pattern
    let mut last_end = 0;
    let mut pending_duration: Option<u32> = None;

    for cap in time_pattern.captures_iter(notes) {
        let full_match = cap.get(0).unwrap();
        let minutes: u32 = cap.get(1).unwrap().as_str().parse().unwrap_or(0);
        let seconds: u32 = cap.get(2).unwrap().as_str().parse().unwrap_or(0);
        let duration = minutes * 60 + seconds;

        // Get text before this [time] tag
        let text_before = &notes[last_end..full_match.start()];
        let cleaned_text = clean_text_for_display(text_before);

        if !cleaned_text.trim().is_empty() {
            segments.push(TeleprompterSegment {
                text: cleaned_text,
                duration_seconds: pending_duration,
                start_time_seconds: cumulative_time,
            });

            if let Some(d) = pending_duration {
                cumulative_time += d;
            }
        }

        pending_duration = Some(duration);
        has_any_timing = true;
        last_end = full_match.end();
    }

    // Handle remaining text after last [time] tag
    let remaining_text = &notes[last_end..];
    let cleaned_remaining = clean_text_for_display(remaining_text);

    if !cleaned_remaining.trim().is_empty() {
        segments.push(TeleprompterSegment {
            text: cleaned_remaining,
            duration_seconds: pending_duration,
            start_time_seconds: cumulative_time,
        });

        if let Some(d) = pending_duration {
            cumulative_time += d;
        }
    }

    // If no segments were created (no [time] tags), create one segment with all content
    if segments.is_empty() && !notes.trim().is_empty() {
        segments.push(TeleprompterSegment {
            text: clean_text_for_display(notes),
            duration_seconds: None,
            start_time_seconds: 0,
        });
    }

    // Calculate total duration (only if all segments have timing)
    let total_duration = if has_any_timing && segments.iter().all(|s| s.duration_seconds.is_some()) {
        Some(segments.iter().filter_map(|s| s.duration_seconds).sum())
    } else {
        None
    };

    TeleprompterContent {
        segments,
        total_duration_seconds: total_duration,
        has_timing: has_any_timing,
    }
}

/// Clean text for display in teleprompter
/// - Removes [time mm:ss] tags
/// - Preserves [note content] tags (will be styled pink)
/// - Normalizes whitespace
fn clean_text_for_display(text: &str) -> String {
    let time_pattern = regex::Regex::new(r"\[time\s+\d{1,2}:\d{2}\]").unwrap();

    // Remove [time] tags
    let cleaned = time_pattern.replace_all(text, "");

    // Normalize line breaks and trim
    cleaned
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .trim()
        .to_string()
}

/// Format [note content] tags for display
/// Returns HTML-like markup for styling
pub fn format_notes_for_display(text: &str) -> String {
    let note_pattern = regex::Regex::new(r"\[note\s+([^\]]+)\]").unwrap();

    note_pattern.replace_all(text, |caps: &regex::Captures| {
        let content = caps.get(1).map_or("", |m| m.as_str());
        format!("<note>{}</note>", content)
    }).to_string()
}

/// Calculate scroll speed for a segment
///
/// # Arguments
/// * `segment_height` - Height of the segment in pixels
/// * `duration_seconds` - Duration for the segment
/// * `default_speed` - Default speed in pixels per second
pub fn calculate_scroll_speed(
    segment_height: f32,
    duration_seconds: Option<u32>,
    default_speed: f32,
) -> f32 {
    match duration_seconds {
        Some(duration) if duration > 0 => segment_height / duration as f32,
        _ => default_speed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_notes_with_timing() {
        let notes = r#"Welcome! [time 00:30]
This is the first section.

[time 01:00]
This is the second section.
[note remember to pause]

No timing here."#;

        let content = parse_notes_to_segments(notes);

        assert_eq!(content.segments.len(), 3);
        assert!(content.has_timing);

        // First segment has no timing (text before first [time])
        assert!(content.segments[0].duration_seconds.is_none());

        // Second segment has 30 seconds
        assert_eq!(content.segments[1].duration_seconds, Some(30));

        // Third segment has 60 seconds
        assert_eq!(content.segments[2].duration_seconds, Some(60));
    }

    #[test]
    fn test_parse_notes_without_timing() {
        let notes = "Just some text without any timing.";

        let content = parse_notes_to_segments(notes);

        assert_eq!(content.segments.len(), 1);
        assert!(!content.has_timing);
        assert!(content.segments[0].duration_seconds.is_none());
    }

    #[test]
    fn test_format_notes_for_display() {
        let text = "Hello [note smile] world [note pause]!";
        let formatted = format_notes_for_display(text);

        assert_eq!(formatted, "Hello <note>smile</note> world <note>pause</note>!");
    }
}
