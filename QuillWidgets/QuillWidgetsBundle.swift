import SwiftUI
import WidgetKit

@main
struct QuillWidgetsBundle: WidgetBundle {
	var body: some Widget {
		CertificateWidget()
		LibraryWidget()
		QuillProgressActivityWidget()
		if #available(iOS 18.0, *) {
			ImportIPAControl()
			PasteLinkControl()
			SignLatestControl()
			CertificateStatusControl()
		}
	}
}
