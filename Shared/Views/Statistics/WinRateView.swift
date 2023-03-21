import SwiftUI
import ValorantAPI
import Charts
import Collections

private typealias WinRate = Statistics.WinRate
private typealias Tally = WinRate.Tally
private typealias Side = WinRate.Side

@available(iOS 16.0, *)
struct WinRateView: View {
	var statistics: Statistics
	var winRate: Statistics.WinRate { statistics.winRate }
	
	@AppStorage("WinRateView.shouldNormalize")
	var shouldNormalize = false
	
	@Environment(\.assets) private var assets
	
	var stacking: MarkStackingMethod {
		shouldNormalize ? .normalized : .standard
	}
	
    var body: some View {
		List {
			Section("Over Time") {
				chartOverTime()
			}
			
			Section("By Map") {
				byMap()
			}
			
			Section("Rounds by Side") {
				roundsBySide()
			}
			
			Section("Rounds by Loadout Delta") {
				roundsByLoadoutDelta()
			}
		}
		.toolbar {
			ToolbarItemGroup(placement: .bottomBar) {
				Toggle("Normalize Charts", isOn: $shouldNormalize.animation(.easeInOut))
					.padding(.vertical)
			}
		}
		.navigationTitle("Win Rate")
    }
	
	@State var timeGrouping = DateBinSize.day
	
	@ViewBuilder
	func chartOverTime() -> some View {
		Chart {
			// transposing the data like this means we can let Charts group the data automatically, stacking up all outcomes of one type before any of the next type
			let data: [(day: Date, entry: Tally.Entry)] = winRate.byDay
				.map { day, tally in tally.data().map { (day, $0) } }
				.flatTransposed()
			
			ForEach(data.indexed(), id: \.index) { index, data in
				BarMark(
					x: .value("Day", data.day, unit: timeGrouping.component),
					y: .value("Count", data.entry.count),
					stacking: stacking
				)
				.foregroundStyle(by: .value("Outcome", data.entry.name))
			}
			
			if shouldNormalize {
				RuleMark(y: .value("Count", 50))
					.lineStyle(.init(lineWidth: 1, dash: [4, 2]))
					.foregroundStyle(Color.secondary)
			}
		}
		.chartForegroundStyleScale(Tally.foregroundStyleScale)
		.chartXAxis {
			AxisMarks(position: .bottom)
		}
		.chartYAxis { maybePercentageLabels() }
		.aligningListRowSeparator()
		.padding(.vertical)
		
		Picker("Group by", selection: $timeGrouping) {
			ForEach(DateBinSize.allCases, id: \.self) { size in
				Text(size.name).tag(size)
			}
		}
	}
	
	@State private var startingSideFilter: Side?
	
	@ScaledMetric(relativeTo: .callout)
	private var mapRowHeight = 35
	
	@ViewBuilder
	func byMap() -> some View {
		Group {
			let data: [MapID: Tally] = startingSideFilter.map { winRate.byStartingSide[$0] ?? [:] } ?? winRate.byMap
			winRateByMap(entries: [("All Maps", data.values.reduce(into: .zero, +=) )])
				.chartLegend(.hidden)
			
			let maps = winRate.byMap.keys
			winRateByMap(entries: maps.map { map in (name(for: map), data[map] ?? .zero) })
				.chartYScale(domain: .automatic(dataType: String.self) { $0.sort() })
		}
		.chartForegroundStyleScale(Tally.foregroundStyleScale)
		.chartXScale(domain: .automatic(dataType: Int.self) { domain in
			if !shouldNormalize, startingSideFilter != nil {
				let max = winRate.byStartingSide.values
					.lazy
					.flatMap(\.values)
					.map(\.total)
					.max() ?? 0
				domain.append(max) // consistent scale across views
			}
		})
		.chartXAxis { maybePercentageLabels() }
		.chartYAxis { boldLabels() }
		.aligningListRowSeparator()
		
		VStack(spacing: 8) {
			Text("Starting Side:")
				.font(.callout)
				.frame(maxWidth: .infinity, alignment: .leading)
			Picker("Starting Side", selection: $startingSideFilter) {
				Text("Total").tag(nil as Side?)
				Text("Attacking").tag(.attacking as Side?)
				Text("Defending").tag(.defending as Side?)
			}
			.pickerStyle(.segmented)
			
			Text("Filtering by starting side will exclude any matches in single-round modes like Deathmatch, Escalation, etc.")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
	
	private func winRateByMap(entries: [(map: String, tally: Tally)]) -> some View {
		Chart(entries, id: \.map) { map, tally in
			marks(for: tally, y: .value("Map", map))
		}
		.chartPlotStyle { $0
			.frame(height: .init(entries.count) * mapRowHeight)
		}
		.chartOverlay { chart in
			ForEach(entries, id: \.map) { map, tally in
				chart.rowLabel(y: map) {
					Group {
						if tally.total > 0 {
							Text(tally.winFraction, format: .precisePercent)
						} else {
							Text("No data")
						}
					}
					.padding(.horizontal, 0.15 * mapRowHeight)
				}
			}
		}
	}
	
	@ScaledMetric(relativeTo: .caption2)
	private var sideRowHeight = 25
	
	@ViewBuilder
	func roundsBySide() -> some View {
		Grid(verticalSpacing: 12) {
			let total: [Side: Tally] = winRate.roundsBySide.values
				.reduce(into: [:]) { $0.merge($1, uniquingKeysWith: +) }
			GridRow(alignment: .top) {
				// tried to use an alignment guide for this, but it doesn't propagate out of .chartOverlay()
				Text("All Maps")
					.font(.callout.weight(.medium))
					.gridColumnAlignment(.leading)
					.frame(height: 0) // to "anchor" offset to center instead of top edge
					.offset(y: sideRowHeight)
				roundsBySide(map: nil, bySide: total)
			}
			
			Divider()
			
			let maps = winRate.roundsBySide.sorted { name(for: $0.key) }
			ForEach(maps, id: \.key) { map, bySide in
				GridRow(alignment: .top) {
					Text(name(for: map))
						.font(.callout.weight(.medium))
						.gridColumnAlignment(.leading)
						.frame(height: 0) // to "anchor" offset to center instead of top edge
						.offset(y: sideRowHeight)
					
					roundsBySide(map: map, bySide: bySide)
						.chartXScale(domain: .automatic(dataType: Int.self) { domain in
							if !shouldNormalize {
								let max = winRate.roundsBySide.values
									.lazy
									.flatMap(\.values)
									.map(\.total)
									.max() ?? 0
								domain.append(max) // consistent domain across charts
							}
						})
						.chartXAxis {
							AxisMarks { value in
								AxisGridLine()
								AxisTick()
								if map == maps.last!.key {
									AxisValueLabel {
										let value = value.as(Int.self)!
										if shouldNormalize {
											Text("\(value)%")
										} else {
											Text("\(value)")
										}
									}
								}
							}
						}
				}
			}
		}
	}
	
	private func sortedMaps(_ keys: some Sequence<MapID?>) -> [MapID?] {
		keys.sorted { $0.map(name(for:)) ?? "" }
	}
	
	private func roundsBySide(map: MapID?, bySide: [Side: Tally]) -> some View {
		Chart {
			ForEach(Array(bySide), id: \.key) { side, tally in
				BarMark(x: .value("Count", tally.wins), y: .value("Side", side.name), stacking: stacking)
					.foregroundStyle(by: .value("Outcome", "Wins"))
				BarMark(x: .value("Count", tally.losses), y: .value("Side", side.name), stacking: stacking)
					.foregroundStyle(by: .value("Outcome", "Losses"))
			}
		}
		.chartOverlay { chart in
			ForEach(Side.allCases, id: \.self) { side in
				chart.rowLabel(y: side.name) {
					Text(bySide[side]!.winFraction, format: .precisePercent)
						.padding(.horizontal, 2)
				}
			}
		}
		.chartPlotStyle { $0
			.frame(height: sideRowHeight * 2)
		}
		.chartYScale(domain: .automatic(dataType: String.self) { $0.sort() })
		.chartYAxis { AxisMarks(preset: .aligned) }
		.chartLegend(.hidden)
		.chartForegroundStyleScale(Tally.foregroundStyleScale)
	}
	
	@ViewBuilder
	func roundsByLoadoutDelta() -> some View {
		Chart {
			let data: [(delta: Int, entry: Tally.Entry)] = winRate.roundsByLoadoutDelta
				.map { delta, tally in tally.data().map { (delta, $0) } }
				.flatTransposed()
			
			ForEach(data, id: \.delta) { delta, entry in
				BarMark(
					x: .value("Loadout Delta", binRange(forDelta: delta)),
					y: .value("Count", Double(entry.count)),
					stacking: stacking
				)
				.foregroundStyle(by: .value("Outcome", entry.name))
			}
		}
		.chartForegroundStyleScale(Tally.foregroundStyleScale)
		.chartXAxisLabel("Value Difference (credits)", alignment: .center)
		.chartLegend(.hidden)
		.chartPlotStyle { $0
			.frame(height: 200)
		}
		.padding(.top)
		.aligningListRowSeparator()
		
		Text("Loadout Delta is computed as the difference between the average loadout value of players on each team. For example, a loadout delta of +1000 means your team's loadouts were an average of 1000 credits more valuable than the enemy team's in that round.")
			.font(.footnote)
			.foregroundStyle(.secondary)
	}
	
	private let deltaBinSize = 200
	private func binRange(forDelta delta: Int) -> Range<Int> {
		let offset = deltaBinSize / 2
		let bin = (Double(delta + offset) / Double(deltaBinSize)).rounded(.down)
		let midpoint = Int(bin) * deltaBinSize
		return midpoint - offset ..< midpoint + offset
	}
	
	private func boldLabels() -> some AxisContent {
		AxisMarks(preset: .aligned) { value in
			AxisValueLabel {
				Text(value.as(String.self)!)
					.font(.callout.weight(.medium))
					.foregroundColor(.primary)
			}
		}
	}
	
	private func maybePercentageLabels() -> some AxisContent {
		AxisMarks { value in
			AxisValueLabel {
				let value = value.as(Int.self)!
				if shouldNormalize {
					Text("\(value)%")
				} else {
					Text("\(value)")
				}
			}
			AxisGridLine()
			AxisTick()
		}
	}
	
	private func marks<Y: Plottable>(for tally: Tally, y: PlottableValue<Y>) -> some ChartContent {
		ForEach(tally.data(), id: \.name) { name, count in
			BarMark(x: .value("Count", count), y: y, stacking: stacking)
				.foregroundStyle(by: .value("Outcome", name))
		}
	}
	
	func value(for map: MapID) -> PlottableValue<String> {
		.value("Map", name(for: map))
	}
	
	func name(for map: MapID) -> String {
		assets?.maps[map]?.displayName ?? map.rawValue
	}
}

@available(iOS 16.0, *)
private extension ChartProxy {
	func rowLabel<Label: View>(
		y: some Plottable,
		@ViewBuilder label: @escaping () -> Label
	) -> some View {
		GeometryReader { geometry in
			if let yRange = positionRange(forY: y) {
				let plotArea = geometry[plotAreaFrame]
				label()
					.font(.caption2)
					.monospacedDigit()
					.foregroundColor(.black.opacity(0.5))
					.blendMode(.hardLight)
					.frame(width: plotArea.width, height: yRange.upperBound - yRange.lowerBound, alignment: .leading)
					.position(x: plotArea.midX, y: (yRange.lowerBound + yRange.upperBound) / 2)
			}
		}
	}
}

extension Side {
	var name: String { // TODO: localize!
		switch self {
		case .attacking:
			return "Attacking"
		case .defending:
			return "Defending"
		}
	}
}

private extension Tally {
	typealias Entry = (name: String, count: Int)
	
	var winFraction: Double {
		.init(wins) / .init(total)
	}
	
	func data() -> [Entry] { // TODO: localize!
		[
			("Wins", wins),
			("Draws", draws),
			("Losses", losses),
		]
	}
	
	static let foregroundStyleScale: KeyValuePairs = [
		"Wins": Color.valorantBlue,
		"Draws": Color.valorantSelf,
		"Losses": Color.valorantRed,
	]
}

#if DEBUG
@available(iOS 16.0, *)
struct WinRateView_Previews: PreviewProvider {
	static var previews: some View {
		WinRateView(statistics: PreviewData.statistics, timeGrouping: .year)
			.withToolbar()
	}
}
#endif
