import Toybox.Lang;
import Toybox.WatchUi;

//! Input for the dial.
//!
//! The dial has nothing to drill into, so this exists to keep the hardware buttons doing what a
//! tactix owner expects: BACK leaves the app, everything else is ignored rather than swallowed.
class DialDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! Returning false lets the system perform its own default action, which for BACK on the
    //! initial view is to exit the app.
    function onBack() as Boolean {
        return false;
    }
}
