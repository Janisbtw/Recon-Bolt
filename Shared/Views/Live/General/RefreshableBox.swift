import SwiftUI

struct RefreshableBox<Content: View>: View {
	var title: String
	var refreshAction: () async -> Void
	@ViewBuilder var content: () -> Content
	// cheeky way of differentiating between these boxes without needing a custom initializer
	@AppStorage("\(Self.self).isExpanded") var isExpanded = true
	
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				expandButton
				
				AsyncButton(action: refreshAction) {
					Image(systemName: "arrow.clockwise")
				}
			}
			.padding()
			
			if isExpanded {
				content()
					.groupBoxStyle(NestedGroupBoxStyle())
			}
		}
		.background(Color(.secondarySystemGroupedBackground))
		.cornerRadius(20)
	}
	
	var expandButton: some View {
		Button {
			withAnimation {
				isExpanded.toggle()
			}
		} label: {
			HStack {
				Image(systemName: "chevron.down")
					.rotationEffect(.degrees(isExpanded ? 0 : -90))
				
				Text(title)
					.foregroundColor(.primary)
				
				Spacer()
			}
			.font(.title2.weight(.semibold))
		}
	}
	
	#if DEBUG
	func forPreviews() -> some View {
		self.padding()
			.background(Color(.systemGroupedBackground))
			.shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
			.previewLayout(.sizeThatFits)
	}
	#endif
	
	private struct NestedGroupBoxStyle: GroupBoxStyle {
		func makeBody(configuration: Configuration) -> some View {
			VStack(spacing: 16) {
				configuration.content
			}
			.frame(maxWidth: .infinity)
			.padding()
			.background(Color(.tertiarySystemGroupedBackground))
			//.cornerRadius(8) // TODO: why
		}
	}
}
