import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Market Sessions for Garmin: live trading hours for the world's exchanges as a 24 hour dial,
//! the third face of the same app alongside the web PWA and the Android home screen widget.
//!
//! The app is entered two ways, and the split matters for memory. The glance list starts it in
//! glance mode under a 64 KB ceiling, where only `(:glance)` annotated code is loaded — the market
//! table, the zone rules, the session maths and `MarketSessionsGlanceView`. Opening it from the
//! glance or the app list starts it normally and brings in `DialView` as well.
class MarketSessionsApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    //! The full screen view, shown when the glance is opened.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new DialView(), new DialDelegate()];
    }

    //! The glance list entry. From API level 4.0.0 an app that does not return one here simply
    //! does not appear in the glance list, so this is what puts Market Sessions on the carousel.
    (:glance)
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new MarketSessionsGlanceView()];
    }
}
