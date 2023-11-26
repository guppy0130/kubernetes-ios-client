//
//  PieChartUsagePercentage.swift
//  kubernetes
//
//  Created by Nick Yang on 2/17/24.
//

import Charts
import SwiftUI
import SwiftkubeModel

struct PieChartUsagePercentage: View {
  private var resource: String
  private var percentageUsed: Double

  init(resource: String, percentageUsed: Double) {
    self.resource = resource
    self.percentageUsed = percentageUsed
  }

  init(resource: String, used: Quantity, total: Quantity) {
    self.resource = resource
    self.percentageUsed = Double(truncating: (used.getValue()! / total.getValue()!) as NSNumber)
  }

  init(resource: String, free: Quantity, total: Quantity) {
    self.resource = resource
    self.percentageUsed = Double(
      truncating: ((total.getValue()! - free.getValue()!) / total.getValue()!) as NSNumber
    )
  }

  init(resource: String, used: Quantity, free: Quantity) {
    self.resource = resource
    self.percentageUsed = Double(
      truncating: (used.getValue()! / (used.getValue()! + free.getValue()!)) as NSNumber
    )
  }

  var body: some View {
    GroupBox(resource) {
      Chart {
        SectorMark(angle: .value("Used", percentageUsed)).foregroundStyle(
          by: .value("UsedOrFree", "Used"))
        SectorMark(angle: .value("Free", 1 - percentageUsed)).foregroundStyle(
          by: .value("UsedOrFree", "Free"))
      }
      .chartForegroundStyleScale([
        "Used": .primary, "Free": .secondary,
      ])
    }
  }
}

struct HorizontalBarChartPercentage: View {
  private var resource: String
  private var percentageUsed: Double

  init(resource: String, percentageUsed: Double) {
    self.resource = resource
    self.percentageUsed = percentageUsed
  }

  init(resource: String, used: Quantity, total: Quantity) {
    self.resource = resource
    self.percentageUsed = Double(truncating: (used.getValue()! / total.getValue()!) as NSNumber)
  }

  init(resource: String, free: Quantity, total: Quantity) {
    self.resource = resource
    self.percentageUsed = Double(
      truncating: ((total.getValue()! - free.getValue()!) / total.getValue()!) as NSNumber
    )
  }

  init(resource: String, used: Quantity, free: Quantity) {
    self.resource = resource
    self.percentageUsed = Double(
      truncating: (used.getValue()! / (used.getValue()! + free.getValue()!)) as NSNumber
    )
  }

  var body: some View {
    GroupBox(resource) {
      Chart {
        BarMark(
          x: .value("Percentage", percentageUsed)
        )
        .foregroundStyle(by: .value("UsedOrFree", "Used"))
        BarMark(
          x: .value("Percentage", 1 - percentageUsed)
        )
        .foregroundStyle(by: .value("UsedOrFree", "Free"))
      }
      .chartForegroundStyleScale([
        "Used": .primary, "Free": .secondary,
      ])
      .chartXAxis(.hidden)
      .chartLegend(.hidden)
      .chartPlotStyle { chartContent in
        chartContent
          .frame(height: 30)
      }
    }
  }
}

#Preview("Pie") {
  PieChartUsagePercentage(resource: "blah", percentageUsed: 0.25)
}

#Preview("Horizontal Bar") {
  HorizontalBarChartPercentage(resource: "blah", percentageUsed: 0.25)
}
