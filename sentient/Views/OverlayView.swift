import SwiftUI

// MARK: - Main Overlay Container

/// Container view that handles navigation between main and settings pages.
struct OverlayView: View {
    /// The ViewModel is injected from AppDelegate.
    /// Using @ObservedObject means this view will re-render when any
    /// @Published property in the ViewModel changes.
    @ObservedObject var viewModel: OverlayViewModel
    
    private let panelWidth: CGFloat = 500
    private let settingsHeight: CGFloat = 380
    
    /// Calculate dynamic height for main page based on response length
    private var mainPageHeight: CGFloat {
        let baseHeight: CGFloat = 360
        let maxHeight: CGFloat = 650
        
        let responseText = viewModel.aiResponse
        if responseText.isEmpty {
            return baseHeight
        }
        
        // Estimate lines: ~55 chars per line at current width, ~22px per line
        let estimatedLines = ceil(Double(responseText.count) / 55.0)
        let additionalHeight = min(CGFloat(estimatedLines) * 22, 250)
        
        return min(baseHeight + additionalHeight, maxHeight)
    }
    
    /// Current height based on which page is active
    private var currentHeight: CGFloat {
        viewModel.currentPage == .main ? mainPageHeight : settingsHeight
    }
    
    var body: some View {
        ZStack {
            // Glass effect background
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            
            // Page content with animation
            Group {
                switch viewModel.currentPage {
                case .main:
                    MainPageView(viewModel: viewModel)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                case .settings:
                    SettingsPageView(viewModel: viewModel)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.currentPage)
        }
        .frame(width: panelWidth, height: currentHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: currentHeight)
    }
}

// MARK: - Preview

#Preview {
    OverlayView(viewModel: OverlayViewModel())
}
