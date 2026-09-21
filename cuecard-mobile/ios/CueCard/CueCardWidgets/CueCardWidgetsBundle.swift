import SwiftUI
import WidgetKit

@main
struct CueCardWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TeleprompterLiveActivity()
        CueCardsLiveActivity()
        if #available(iOS 18.0, *) {
            TeleprompterPlayPauseControl()
            TeleprompterSkipBackControl()
        }
    }
}
