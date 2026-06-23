import SwiftUI

struct StatusBadgeView: View {
    let iconName: String
    let activeCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .semibold))

            if activeCount > 0 {
                Text("\(min(activeCount, 99))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
                    .offset(x: 8, y: -6)
            }
        }
        .frame(width: 22, height: 18)
    }
}
