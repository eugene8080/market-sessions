import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Choosing a theme on the watch itself.
//!
//! Connect IQ's settings framework puts app options in Garmin Connect on the phone, which is the
//! right place for them — when the app came from the store. A sideloaded app is a file copied into
//! GARMIN/APPS, and whether it turns up in Garmin Connect's settings list at all is not something
//! to rely on. So the theme is reachable from the watch too: press MENU on the dial.
//!
//! Both routes write the same `theme` property, so a choice made on the watch survives a phone
//! sync and vice versa.
module ThemeMenu {

    //! The property both routes agree on. Also declared in resources/settings/properties.xml, which
    //! is what makes it appear in Garmin Connect.
    const KEY = "theme";

    //! Read the saved theme and make it live. Called at startup, and again whenever the phone
    //! pushes a settings change.
    function restore() as Void {
        var saved = null;
        try {
            saved = Application.Properties.getValue(KEY);
        } catch (ex) {
            // A property can be absent on first run, or on a device that has never synced.
            saved = null;
        }

        Palette.apply(saved instanceof Number ? saved : Palette.IRON);
    }

    function save(theme as Number) as Void {
        Palette.apply(theme);
        try {
            Application.Properties.setValue(KEY, theme);
        } catch (ex) {
            // Nothing to be done about a device that will not persist it; the theme still applies
            // for this run rather than the press doing visibly nothing.
        }
    }

    //! The menu itself, with the live theme marked.
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({ :title => "Theme" });
        var names = ["Iron", "Cobalt", "Ember"];
        var blurbs = ["Slate and steel", "Deep navy", "Burnt red"];

        for (var theme = 0; theme < Palette.THEME_COUNT; theme += 1) {
            menu.addItem(new WatchUi.MenuItem(
                names[theme],
                theme == Palette.current ? "In use" : blurbs[theme],
                theme,
                null));
        }
        return menu;
    }
}

//! Applies the chosen theme and steps back to the dial.
class ThemeMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        ThemeMenu.save(item.getId() as Number);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.requestUpdate();
    }
}
