import Toybox.Lang;
import Toybox.WatchUi;

//! Choosing the theme and the session colour on the watch itself.
//!
//! Connect IQ's settings framework puts app options in Garmin Connect on the phone, which is the
//! right place for them — when the app came from the store. A sideloaded app is a file copied into
//! GARMIN/APPS, and whether it turns up in Garmin Connect's settings list at all is not something
//! to rely on. So both settings are reachable from the watch: press MENU on the dial.
//!
//! Deliberately **not** `(:glance)`. None of this is reachable from a glance, and pulling Menu2
//! into the glance build would spend memory on a screen it can never show. The persistence lives
//! in Settings.mc, which is annotated, because `onStart` touches it in both modes.
module SettingsMenu {

    var THEME_NAMES as Array<String> = ["Iron", "Cobalt", "Ember"] as Array<String>;
    var THEME_BLURBS as Array<String> = ["Slate and steel", "Deep navy", "Burnt red"] as Array<String>;
    var OPEN_NAMES as Array<String> = ["Red", "Green", "Blue", "Purple"] as Array<String>;

    //! The top level menu: what the MENU button opens.
    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({ :title => "Market Sessions" });
        menu.addItem(new WatchUi.MenuItem("Theme", THEME_NAMES[Palette.current], :theme, null));
        menu.addItem(new WatchUi.MenuItem("Sessions", OPEN_NAMES[Palette.openChoice], :open, null));
        return menu;
    }

    function themeMenu() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({ :title => "Theme" });
        for (var theme = 0; theme < Palette.THEME_COUNT; theme += 1) {
            menu.addItem(new WatchUi.MenuItem(
                THEME_NAMES[theme],
                theme == Palette.current ? "In use" : THEME_BLURBS[theme],
                theme,
                null));
        }
        return menu;
    }

    //! The colour a trading session is drawn in — the one thing on this face that means something
    //! rather than merely setting a mood, which is why it is chosen separately from the theme.
    function openMenu() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({ :title => "Open sessions" });
        for (var choice = 0; choice < Palette.OPEN_COUNT; choice += 1) {
            menu.addItem(new WatchUi.MenuItem(
                OPEN_NAMES[choice],
                choice == Palette.openChoice ? "In use" : null,
                choice,
                null));
        }
        return menu;
    }
}

//! The top level menu: opens one of the two pickers.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :theme) {
            WatchUi.pushView(SettingsMenu.themeMenu(), new ThemeMenuDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            WatchUi.pushView(SettingsMenu.openMenu(), new OpenColourMenuDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

class ThemeMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var theme = item.getId() as Number;
        Palette.apply(theme);
        Settings.write(Settings.THEME_KEY, theme);

        // Back past this menu and the one that opened it, to the dial.
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}

class OpenColourMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var choice = item.getId() as Number;
        Palette.applyOpen(choice);
        Settings.write(Settings.OPEN_KEY, choice);

        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }
}
