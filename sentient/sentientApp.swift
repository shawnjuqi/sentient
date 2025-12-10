import SwiftUI

@main
struct sentientApp: App {
    let persistenceController = PersistenceController.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, 
                    persistenceController.container.viewContext)
        }
    }
}
