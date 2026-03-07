// ExportView.swift
// CSV export UI: generate → share.
// Spec: FR-001 through FR-009
// Feature: 011-csv-import-export WP04 T021

import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSVFile Transferable

struct CSVFile: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(csv.filename)
            try csv.data.write(to: url)
            return SentTransferredFile(url)
        }
        // ProxyRepresentation fallback — fixes iOS 17 Files app issue
        ProxyRepresentation { csv in csv.data }
    }
}

// MARK: - ExportView

struct ExportView: View {

    @State private var viewModel: ExportViewModel

    init(exportService: any ExportServiceProtocol) {
        _viewModel = State(initialValue: ExportViewModel(exportService: exportService))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("Export Training Data")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("Export all your workouts, exercises, and sets as a CSV file. Weights are exported in kilograms.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.isExporting {
                ProgressView("Generating CSV...")
                    .foregroundStyle(Color.textSecondary)
            } else if let data = viewModel.exportData {
                let file = CSVFile(data: data, filename: "workouts-export.csv")
                ShareLink(
                    item: file,
                    preview: SharePreview("workouts-export.csv", image: Image(systemName: "doc.text"))
                ) {
                    Label("Share CSV", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            } else {
                Button {
                    viewModel.generateExport()
                } label: {
                    Label("Export", systemImage: "arrow.down.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
