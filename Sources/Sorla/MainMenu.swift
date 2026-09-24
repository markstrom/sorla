import AppKit

// An accessory app shows no menu bar, but its main menu still handles key equivalents such as ⌘W, ⌘Q and ⌘V.
@MainActor
enum MainMenu {
    static func make(target: AnyObject, about: Selector, settings: Selector) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "Sorla")
        appMenu.addItem(item(String(localized: "About Sorla"), about, target: target))
        appMenu.addItem(.separator())
        appMenu.addItem(item(String(localized: "Settings…"), settings, key: ",", target: target))
        appMenu.addItem(.separator())
        appMenu.addItem(item(String(localized: "Quit Sorla"), #selector(NSApplication.terminate(_:)), key: "q"))
        add(appMenu, to: mainMenu)

        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(item(String(localized: "Close"), #selector(NSWindow.performClose(_:)), key: "w"))
        add(fileMenu, to: mainMenu)

        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(item(String(localized: "Undo"), Selector(("undo:")), key: "z"))
        editMenu.addItem(item(String(localized: "Redo"), Selector(("redo:")), key: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(item(String(localized: "Cut"), #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item(String(localized: "Copy"), #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item(String(localized: "Paste"), #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), key: "a"))
        add(editMenu, to: mainMenu)

        return mainMenu
    }

    private static func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    private static func add(_ submenu: NSMenu, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        mainMenu.addItem(item)
    }
}

// None of Sorla's windows has a Cancel button, so Esc (and ⌘.) closes them like a dialog.
final class SorlaWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
