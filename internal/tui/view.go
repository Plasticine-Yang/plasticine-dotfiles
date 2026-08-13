package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/resultview"
)

type theme struct {
	color bool

	background lipgloss.Color
	surface    lipgloss.Color
	border     lipgloss.Color
	text       lipgloss.Color
	muted      lipgloss.Color
	cyan       lipgloss.Color
	violet     lipgloss.Color
	green      lipgloss.Color
	yellow     lipgloss.Color
	red        lipgloss.Color
}

func newTheme(env map[string]string) theme {
	noColor := false
	if env != nil {
		noColor = env["NO_COLOR"] != ""
	}
	return theme{
		color:      !noColor,
		background: lipgloss.Color("#0B0D12"),
		surface:    lipgloss.Color("#151923"),
		border:     lipgloss.Color("#30384A"),
		text:       lipgloss.Color("#E8ECF5"),
		muted:      lipgloss.Color("#8790A5"),
		cyan:       lipgloss.Color("#50D9FF"),
		violet:     lipgloss.Color("#A78BFA"),
		green:      lipgloss.Color("#69E3A1"),
		yellow:     lipgloss.Color("#F4C76B"),
		red:        lipgloss.Color("#FF7085"),
	}
}

func (t theme) style() lipgloss.Style {
	style := lipgloss.NewStyle()
	if t.color {
		style = style.Foreground(t.text).Background(t.background)
	}
	return style
}

func (t theme) panel() lipgloss.Style {
	style := t.style().Border(lipgloss.RoundedBorder()).Padding(0, 1)
	if t.color {
		style = style.BorderForeground(t.border).Background(t.surface)
	}
	return style
}

func (t theme) accent(text string) string {
	style := lipgloss.NewStyle().Bold(true)
	if t.color {
		style = style.Foreground(t.cyan)
	}
	return style.Render(text)
}

func (t theme) secondary(text string) string {
	style := lipgloss.NewStyle().Bold(true)
	if t.color {
		style = style.Foreground(t.violet)
	}
	return style.Render(text)
}

func (t theme) subdued(text string) string {
	style := lipgloss.NewStyle()
	if t.color {
		style = style.Foreground(t.muted)
	}
	return style.Render(text)
}

func (t theme) status(status string, text string) string {
	style := lipgloss.NewStyle().Bold(true)
	if t.color {
		switch status {
		case "success":
			style = style.Foreground(t.green)
		case "warning":
			style = style.Foreground(t.yellow)
		case "error":
			style = style.Foreground(t.red)
		default:
			style = style.Foreground(t.cyan)
		}
	}
	return style.Render(text)
}

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Starting Plasticine..."
	}
	if m.width < 60 || m.height < 18 {
		return m.renderResize()
	}

	header := m.renderHeader()
	bodyHeight := max(5, m.height-lipgloss.Height(header)-3)
	body := m.renderBody(m.width, bodyHeight)
	footer := m.renderFooter()
	frame := lipgloss.JoinVertical(lipgloss.Left, header, body, footer)
	frame = m.theme.style().Width(m.width).Height(m.height).Render(frame)
	if m.dialog != dialogNone {
		frame = m.renderDialog(frame)
	}
	return frame
}

func (m model) renderResize() string {
	content := strings.Join([]string{
		m.theme.accent("PLASTICINE"),
		"",
		"Terminal is too small",
		m.theme.subdued(fmt.Sprintf("Current %dx%d · minimum 60x18", m.width, m.height)),
		"",
		"Resize the terminal to continue.",
		"Ctrl-C exits safely.",
	}, "\n")
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, content)
}

func (m model) renderHeader() string {
	title := m.theme.accent("PLASTICINE")
	version := m.theme.subdued(m.runtime.Version.Version + "  " + m.runtime.Target.String())
	left := title + "  " + version

	tabs := []string{"1 Dashboard", "2 Plan", "3 Components", "4 Doctor"}
	for index := range tabs {
		if screen(index) == m.screen {
			tabs[index] = m.theme.secondary("● " + tabs[index])
		} else {
			tabs[index] = m.theme.subdued("○ " + tabs[index])
		}
	}
	right := strings.Join(tabs, "   ")
	var line string
	if m.width < 100 {
		line = " " + left + "\n " + right
	} else {
		gap := max(1, m.width-lipgloss.Width(left)-lipgloss.Width(right)-4)
		line = " " + left + strings.Repeat(" ", gap) + right + " "
	}
	border := lipgloss.NewStyle().BorderBottom(true).BorderStyle(lipgloss.NormalBorder())
	if m.theme.color {
		border = border.BorderForeground(m.theme.border)
	}
	return border.Width(m.width).Render(line)
}

func (m model) renderFooter() string {
	status := m.status
	if m.operationCancel {
		status = "Canceling safely; waiting for the current operation..."
	}
	if m.err != nil {
		status = m.err.Error()
	}
	left := m.theme.subdued("p plan  a apply  d doctor  ? help  q quit")
	right := m.theme.status(statusClass(m.err, m.latestResult), truncateMiddle(status, max(12, m.width/2)))
	gap := max(1, m.width-lipgloss.Width(left)-lipgloss.Width(right)-4)
	return " " + left + strings.Repeat(" ", gap) + right + " "
}

func (m model) renderBody(width int, height int) string {
	switch m.screen {
	case screenPlan:
		return m.renderPlan(width, height)
	case screenComponents:
		return m.renderComponents(width, height)
	case screenDoctor:
		return m.renderDoctor(width, height)
	default:
		return m.renderDashboard(width, height)
	}
}

func (m model) renderDashboard(width int, height int) string {
	if width < 100 || height < 20 {
		session := "No plan loaded"
		if m.latestResult != nil {
			session = string(m.latestResult.Outcome)
		}
		compact := m.theme.panel().Width(max(34, width-6)).Render(strings.Join([]string{
			m.theme.subdued("WORKSTATION DASHBOARD"),
			m.theme.accent(m.runtime.Version.Version) + " · " + m.theme.secondary(m.runtime.Target.String()),
			"",
			"Session  " + m.theme.status(outcomeClass(m.latestResult), session),
			"",
			"p Plan    a Apply    d Doctor",
			m.theme.subdued("Startup runs no Plan, network access, or mutation."),
		}, "\n"))
		return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, compact)
	}
	cardWidth := max(20, (width-8)/3)
	versionCard := m.theme.panel().Width(cardWidth).Render(strings.Join([]string{
		m.theme.subdued("RELEASE"),
		m.theme.accent(m.runtime.Version.Version),
		m.theme.subdued("commit " + truncateMiddle(m.runtime.Version.Commit, cardWidth-10)),
	}, "\n"))
	targetCard := m.theme.panel().Width(cardWidth).Render(strings.Join([]string{
		m.theme.subdued("ARTIFACT TARGET"),
		m.theme.secondary(m.runtime.Target.String()),
		m.theme.subdued(string(m.runtime.Host.Family) + " " + m.runtime.Host.Version),
	}, "\n"))
	sessionText := "No plan loaded"
	if m.latestResult != nil {
		sessionText = string(m.latestResult.Outcome)
	}
	sessionCard := m.theme.panel().Width(cardWidth).Render(strings.Join([]string{
		m.theme.subdued("CURRENT SESSION"),
		m.theme.status(outcomeClass(m.latestResult), sessionText),
		m.theme.subdued(m.sessionSummary()),
	}, "\n"))

	var cards string
	if width >= 100 {
		cards = lipgloss.JoinHorizontal(lipgloss.Top, versionCard, " ", targetCard, " ", sessionCard)
	} else {
		cards = lipgloss.JoinVertical(lipgloss.Left, versionCard, targetCard, sessionCard)
	}
	actions := m.theme.panel().Width(max(30, width-6)).Render(strings.Join([]string{
		m.theme.accent("Owner actions"),
		"",
		"p  Build a complete read-only Plan",
		"a  Build, review, and Apply one immutable Plan",
		"d  Run local and bounded online Doctor checks",
		"",
		m.theme.subdued("Startup performs no Plan, Reconciliation State read, network access, or mutation."),
	}, "\n"))
	content := lipgloss.JoinVertical(lipgloss.Left, cards, "", actions)
	return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, content)
}

func (m model) renderPlan(width int, height int) string {
	if m.planResult == nil {
		if m.operation == "apply" || m.operation == "plan" {
			return m.renderProgress(width, height)
		}
		empty := m.theme.panel().Width(max(32, width-10)).Render(strings.Join([]string{
			m.theme.accent("No plan loaded"),
			"",
			"Press p to build a read-only Plan.",
			"Press a to build the exact Apply Plan and review authorization.",
		}, "\n"))
		return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, empty)
	}
	if m.operation == "apply" && len(m.progressLog) > 0 && m.dialog == dialogNone {
		return m.renderProgress(width, height)
	}
	view := resultview.Project("plan", *m.planResult)
	listWidth := 30
	if width >= 120 {
		listWidth = 34
	}
	list := m.renderPlanList(view, listWidth, height-2)
	detailWidth := max(24, width-listWidth-7)
	detail := m.renderPlanDetail(view, detailWidth, height-2)
	if width >= 100 {
		return lipgloss.PlaceHorizontal(width, lipgloss.Center,
			lipgloss.JoinHorizontal(lipgloss.Top, list, "  ", detail))
	}
	if m.detailFocused {
		return lipgloss.PlaceHorizontal(width, lipgloss.Center, detail)
	}
	return lipgloss.PlaceHorizontal(width, lipgloss.Center, list)
}

func (m model) renderPlanList(view resultview.View, width int, height int) string {
	lines := []string{
		m.theme.subdued("PLAN OVERVIEW"),
		m.theme.status(outcomeClass(m.planResult), string(m.planResult.Outcome)),
		"",
	}
	summaryPrefix := "  "
	if m.planCursor == 0 {
		summaryPrefix = "› "
	}
	lines = append(lines, summaryPrefix+"◆ Summary")
	components := planComponents(*m.planResult)
	if len(components) == 0 {
		lines = append(lines, m.theme.subdued("No Component-specific work"))
	}
	visibleRows := max(1, height-7)
	start, end := visibleWindow(len(components), max(0, m.planCursor-1), visibleRows)
	if start > 0 {
		lines = append(lines, m.theme.subdued("  ↑ more Components"))
	}
	for index := start; index < end; index++ {
		component := components[index]
		prefix := "  "
		if index+1 == m.planCursor {
			prefix = "› "
		}
		status := componentStatus(view, component)
		lines = append(lines, prefix+statusGlyph(status)+" "+string(component))
	}
	if end < len(components) {
		lines = append(lines, m.theme.subdued("  ↓ more Components"))
	}
	lines = append(lines, "", m.theme.subdued(fmt.Sprintf("%d changes · %d risks", len(m.planResult.Changes), len(view.Risks))))
	if m.width < 100 {
		lines = append(lines, "", m.theme.subdued("Enter/Tab opens details"))
	}
	return m.theme.panel().Width(width).Height(height).Render(strings.Join(lines, "\n"))
}

func (m model) renderPlanDetail(view resultview.View, width int, height int) string {
	content := m.planDetailContent(view, width-4)
	copy := m.viewport
	copy.Width = width - 4
	copy.Height = height - 2
	copy.SetContent(content)
	return m.theme.panel().Width(width).Height(height).Render(copy.View())
}

func (m model) planDetailContent(view resultview.View, width int) string {
	component := selectedPlanComponent(*m.planResult, m.planCursor)
	var sections []string
	sections = append(sections, m.theme.subdued("PLAN DETAILS"))
	if component != "" {
		sections = append(sections, m.theme.accent(string(component)), "")
	} else {
		sections = append(sections, m.theme.accent("Summary"), "")
	}
	sections = append(sections, fmt.Sprintf("Outcome  %s", m.planResult.Outcome))
	sections = append(sections, fmt.Sprintf("Support  %s", m.planResult.Support.Level))
	sections = append(sections, fmt.Sprintf("Scope    %d active · %d excluded · %d suspended",
		len(m.planResult.Scope.Active), len(m.planResult.Scope.Excluded), len(m.planResult.Scope.Suspended)))

	risks := filterRisks(view.Risks, component)
	if len(risks) > 0 {
		sections = append(sections, "", m.theme.status("warning", "Risks"))
		for _, risk := range risks {
			sections = append(sections, "• "+riskLine(risk, width-6))
		}
	}
	changes := filterChanges(view.Changes, component)
	if len(changes) > 0 {
		sections = append(sections, "", m.theme.secondary("Changes"))
		for _, group := range changes {
			for _, kind := range group.Kinds {
				sections = append(sections, m.theme.subdued(kind.Kind))
				for _, change := range kind.Changes {
					path := change.Path
					if path == "" {
						path = "(no path)"
					}
					sections = append(sections, "• "+truncateMiddle(path, width-8))
					sections = append(sections, "  "+change.Summary)
				}
			}
		}
	}
	if component == "" && len(view.NextActions) > 0 {
		sections = append(sections, "", m.theme.accent("Next Actions"))
		for _, action := range view.NextActions {
			sections = append(sections, "• "+action)
		}
	}
	return strings.Join(sections, "\n")
}

func (m model) renderComponents(width int, height int) string {
	if width < 100 || height < 18 {
		return m.renderCompactComponents(width, height)
	}
	columnWidth := max(28, (width-9)/2)
	scopeLines := []string{m.theme.subdued("WORKSTATION SCOPE DRAFT")}
	runLines := []string{m.theme.subdued("ONE-RUN COMPONENT FILTER")}
	for index, component := range m.catalog {
		scopeCursor := index == m.componentCursor && m.column == columnScope
		runCursor := index == m.componentCursor && m.column == columnRun
		scopeLines = append(scopeLines, optionLine(scopeCursor, !m.scopeExcluded[component.ID], string(component.ID)))
		runLines = append(runLines, optionLine(runCursor, m.filterSelected[component.ID], string(component.ID)))
		if len(component.Dependencies) > 0 {
			dependency := "requires " + joinComponentIDs(component.Dependencies)
			scopeLines = append(scopeLines, "    "+m.theme.subdued(dependency))
			runLines = append(runLines, "    "+m.theme.subdued(dependency))
		}
	}
	scopeState := "saved"
	if !m.scopeKnown {
		scopeState = "loaded on first Plan"
	}
	if m.scopeDirty {
		scopeState = "draft · not persisted"
	}
	scopeLines = append(scopeLines, "", m.theme.subdued(scopeState))
	runLines = append(runLines, "",
		optionLine(m.componentCursor == len(m.catalog), m.skipLoginShell, "skip login-shell change"),
		optionLine(m.componentCursor == len(m.catalog)+1, m.adoptConflicts, "adopt conflicts"),
		"",
		m.theme.subdued("Run Settings last only for this session."),
	)
	scopePanel := m.theme.panel().Width(columnWidth).Height(max(14, height-7)).Render(strings.Join(scopeLines, "\n"))
	runPanel := m.theme.panel().Width(columnWidth).Height(max(14, height-7)).Render(strings.Join(runLines, "\n"))

	var columns string
	if width >= 100 {
		columns = lipgloss.JoinHorizontal(lipgloss.Top, scopePanel, "  ", runPanel)
	} else {
		active := scopePanel
		if m.column == columnRun || m.componentCursor >= len(m.catalog) {
			active = runPanel
		}
		columns = active
	}
	messages := m.validationMessages()
	validation := m.theme.panel().Width(max(30, width-7)).Render(m.renderValidation(messages))
	return lipgloss.PlaceHorizontal(width, lipgloss.Center,
		lipgloss.JoinVertical(lipgloss.Left, columns, "", validation))
}

func (m model) renderCompactComponents(width int, height int) string {
	runFocus := m.column == columnRun || m.componentCursor >= len(m.catalog)
	title := "WORKSTATION SCOPE DRAFT"
	var rows []string
	if runFocus {
		title = "ONE-RUN FILTER & SETTINGS"
		for index, component := range m.catalog {
			rows = append(rows, optionLine(index == m.componentCursor, m.filterSelected[component.ID], string(component.ID)))
		}
		rows = append(rows,
			optionLine(m.componentCursor == len(m.catalog), m.skipLoginShell, "skip login-shell change"),
			optionLine(m.componentCursor == len(m.catalog)+1, m.adoptConflicts, "adopt conflicts"),
		)
	} else {
		for index, component := range m.catalog {
			rows = append(rows, optionLine(index == m.componentCursor, !m.scopeExcluded[component.ID], string(component.ID)))
		}
	}
	visibleRows := max(2, height-7)
	cursor := min(m.componentCursor, len(rows)-1)
	start, end := visibleWindow(len(rows), cursor, visibleRows)
	lines := []string{m.theme.subdued(title)}
	if start > 0 {
		lines = append(lines, m.theme.subdued("  ↑ more"))
	}
	lines = append(lines, rows[start:end]...)
	if end < len(rows) {
		lines = append(lines, m.theme.subdued("  ↓ more"))
	}
	state := "Tab switches Scope and Run Settings"
	if m.scopeDirty {
		state = "Scope draft changed · Plan required"
	}
	lines = append(lines, m.theme.subdued(state))
	if messages := m.validationMessages(); len(messages) > 0 {
		lines = append(lines, m.theme.status("error", truncateMiddle(messages[0], width-10)))
	} else {
		lines = append(lines, m.theme.status("success", "✓ Selection is structurally valid"))
	}
	panel := m.theme.panel().Width(max(30, width-6)).Height(max(7, height-2)).Render(strings.Join(lines, "\n"))
	return lipgloss.PlaceHorizontal(width, lipgloss.Center, panel)
}

func (m model) renderValidation(messages []string) string {
	if len(messages) == 0 {
		return m.theme.status("success", "✓ Selection is structurally valid")
	}
	lines := []string{m.theme.status("error", "Invalid selection")}
	for _, message := range messages {
		lines = append(lines, "• "+message)
	}
	lines = append(lines, m.theme.subdued("Reconciler remains the final policy gate."))
	return strings.Join(lines, "\n")
}

func (m model) renderDoctor(width int, height int) string {
	if m.doctorResult == nil {
		if m.operation == "doctor" {
			return m.renderProgress(width, height)
		}
		empty := m.theme.panel().Width(max(32, width-10)).Render(strings.Join([]string{
			m.theme.accent("Doctor has not run"),
			"",
			"Press d to run local diagnostics and bounded online checks.",
		}, "\n"))
		return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, empty)
	}
	view := resultview.Project("doctor", *m.doctorResult)
	content := m.doctorContent(view)
	copy := m.viewport
	copy.Width = max(20, width-10)
	copy.Height = max(5, height-4)
	copy.SetContent(content)
	panel := m.theme.panel().Width(max(32, width-6)).Height(height - 2).Render(copy.View())
	return lipgloss.PlaceHorizontal(width, lipgloss.Center, panel)
}

func (m model) doctorContent(view resultview.View) string {
	lines := []string{
		m.theme.subdued("DOCTOR"),
		m.theme.status(outcomeClass(m.doctorResult), string(m.doctorResult.Outcome)),
		fmt.Sprintf("%d healthy · %d unhealthy", view.HealthyCount, view.UnhealthyCount),
	}
	for _, group := range view.Checks {
		lines = append(lines, "", m.theme.secondary(group.Category))
		for _, check := range group.Checks {
			status := "success"
			glyph := "✓"
			if !check.Healthy {
				status = "error"
				glyph = "×"
			}
			lines = append(lines, m.theme.status(status, glyph)+" "+check.Name)
			lines = append(lines, "  "+check.Message)
		}
	}
	if len(view.NextActions) > 0 {
		lines = append(lines, "", m.theme.accent("Next Actions"))
		for _, action := range view.NextActions {
			lines = append(lines, "• "+action)
		}
	}
	return strings.Join(lines, "\n")
}

func (m model) renderProgress(width int, height int) string {
	content := m.progressContent(width - 10)
	copy := m.viewport
	copy.Width = max(20, width-10)
	copy.Height = max(5, height-5)
	copy.SetContent(content)
	panel := m.theme.panel().Width(max(34, width-6)).Height(height - 2).Render(copy.View())
	return lipgloss.PlaceHorizontal(width, lipgloss.Center, panel)
}

func (m model) progressContent(width int) string {
	lines := []string{
		m.theme.subdued(strings.ToUpper(m.operation) + " PROGRESS"),
		m.theme.accent(m.status),
	}
	if m.currentChange != nil {
		lines = append(lines, "",
			m.theme.secondary("Current Change"),
			fmt.Sprintf("%s · %s", m.currentChange.Component, m.currentChange.ChangeKind),
			truncateMiddle(m.currentChange.Path, width-12),
		)
	}
	lines = append(lines, "", m.theme.subdued("EVENT LOG"))
	for _, event := range m.progressLog {
		lines = append(lines, progressLine(event, width-10))
	}
	if len(m.progressLog) == 0 {
		lines = append(lines, m.theme.subdued("Waiting for the first event..."))
	}
	return strings.Join(lines, "\n")
}

func (m model) renderDialog(base string) string {
	var content string
	width := min(72, max(42, m.width-10))
	switch m.dialog {
	case dialogHelp:
		content = strings.Join([]string{
			m.theme.accent("Keyboard help"),
			"",
			"1-4       Switch screens",
			"p / a / d Plan, Apply, Doctor",
			"↑↓ / j k  Move selection or scroll",
			"Tab       Switch focus or column",
			"Enter     Open details or confirm",
			"Space     Toggle a setting",
			"? / Esc   Close help",
			"q         Quit while idle",
			"Ctrl-C    Cancel safely and exit 130",
		}, "\n")
	case dialogDiscard:
		content = strings.Join([]string{
			m.theme.status("warning", "Discard Workstation Scope draft?"),
			"",
			"The draft has not been persisted through Apply.",
			"",
			"y / Enter  discard and quit",
			"n / Esc    keep working",
		}, "\n")
	case dialogAuthorization:
		lines := []string{
			m.theme.status("warning", "Authorize exact Apply Plan"),
			m.theme.subdued(fmt.Sprintf("%d changes · %d conflicts · %d retirements",
				len(m.authResult.Changes), len(m.authResult.Conflicts), len(m.authResult.Retirements))),
			"",
		}
		for index, item := range m.authItems {
			lines = append(lines, optionLine(index == m.authCursor, item.checked, item.label))
		}
		riskLines := authorizationRiskLines(m.authResult, width-6)
		visibleRisks := max(1, m.height-len(m.authItems)-13)
		maxOffset := max(0, len(riskLines)-visibleRisks)
		offset := min(m.authRiskOffset, maxOffset)
		end := min(len(riskLines), offset+visibleRisks)
		riskHeading := fmt.Sprintf("EXACT RISKS IN THIS PLAN  %d-%d/%d", offset+1, end, len(riskLines))
		lines = append(lines, "", m.theme.subdued(riskHeading))
		lines = append(lines, riskLines[offset:end]...)
		lines = append(lines, "",
			m.theme.subdued("PgUp/PgDn or mouse wheel scrolls risks"),
			m.theme.subdued("Space toggles · Enter approves only when all are checked"),
			m.theme.subdued("Esc denies with zero mutation"),
		)
		content = strings.Join(lines, "\n")
	case dialogGitHubKey:
		content = strings.Join([]string{
			m.theme.accent("GitHub SSH private-key path"),
			"",
			"Plasticine validates this external Secret and persists only",
			"its path and public fingerprint as a Secret Reference.",
			"",
			m.keyInput.View(),
			"",
			m.theme.subdued("Enter selects · Esc cancels · key contents are never displayed"),
		}, "\n")
	case dialogTerminal:
		content = strings.Join([]string{
			m.theme.accent("Terminal handed to system command"),
			"",
			"Plasticine temporarily suspended the full-screen renderer.",
			"The command owns the controlling terminal until it returns.",
		}, "\n")
	default:
		return base
	}
	dialog := m.theme.panel().Width(width).Render(content)
	if m.theme.color {
		return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, dialog,
			lipgloss.WithWhitespaceChars(" "),
			lipgloss.WithWhitespaceForeground(m.theme.background),
		)
	}
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, dialog)
}

func authorizationRiskLines(result reconciler.Result, width int) []string {
	var lines []string
	for _, change := range result.Changes {
		if change.SystemChange {
			lines = append(lines, "• System Change · "+truncateMiddle(change.Summary, width-18))
		}
		if change.Kind == reconciler.ChangeRunExternalInstaller {
			lines = append(lines,
				"• External Script · "+string(change.Component),
				"  "+truncateMiddle(change.Path, width-2),
				"  "+truncateMiddle(change.Summary, width-2),
			)
		}
	}
	for _, conflict := range result.Conflicts {
		if conflict.Adoptable {
			lines = append(lines, "• Adoption · "+truncateMiddle(conflict.Path, width-13))
		}
	}
	for _, retirement := range result.Retirements {
		lines = append(lines, "• Retirement · "+truncateMiddle(retirement.Path, width-15))
	}
	if len(lines) == 0 {
		lines = append(lines, "• No elevated risk classes")
	}
	return lines
}

func (m model) sessionSummary() string {
	if m.operation != "" {
		return m.operation + " in progress"
	}
	if m.latestResult == nil {
		return "No plan loaded"
	}
	return fmt.Sprintf("%d changes · %d blockers", len(m.latestResult.Changes), len(m.latestResult.Blockers))
}

func statusClass(err error, result *reconciler.Result) string {
	if err != nil {
		return "error"
	}
	return outcomeClass(result)
}

func outcomeClass(result *reconciler.Result) string {
	if result == nil {
		return "info"
	}
	switch result.Outcome {
	case reconciler.OutcomeApplied, reconciler.OutcomeNoChange, reconciler.OutcomeHealthy:
		return "success"
	case reconciler.OutcomeChangesPlanned:
		return "info"
	case reconciler.OutcomeDenied:
		return "warning"
	default:
		return "error"
	}
}

func optionLine(cursor bool, checked bool, label string) string {
	prefix := "  "
	if cursor {
		prefix = "› "
	}
	marker := "○"
	if checked {
		marker = "●"
	}
	return prefix + marker + " " + label
}

func statusGlyph(status string) string {
	switch status {
	case "blocked":
		return "×"
	case "skipped", "suspended":
		return "○"
	case "succeeded", "healthy":
		return "✓"
	case "will-change":
		return "◆"
	default:
		return "•"
	}
}

func planComponents(result reconciler.Result) []reconciler.ComponentID {
	seen := map[reconciler.ComponentID]bool{}
	var components []reconciler.ComponentID
	add := func(component reconciler.ComponentID) {
		if component == "" || seen[component] {
			return
		}
		seen[component] = true
		components = append(components, component)
	}
	for _, component := range result.Scope.Active {
		add(component)
	}
	for _, component := range result.Components {
		add(component.Component)
	}
	for _, change := range result.Changes {
		add(change.Component)
	}
	return components
}

func selectedPlanComponent(result reconciler.Result, cursor int) reconciler.ComponentID {
	components := planComponents(result)
	if cursor <= 0 || len(components) == 0 {
		return ""
	}
	return components[min(cursor-1, len(components)-1)]
}

func componentStatus(view resultview.View, component reconciler.ComponentID) string {
	for _, group := range view.Components {
		for _, candidate := range group.Components {
			if candidate == component {
				return group.Status
			}
		}
	}
	return "active"
}

func filterRisks(risks []resultview.Risk, component reconciler.ComponentID) []resultview.Risk {
	if component == "" {
		return risks
	}
	var filtered []resultview.Risk
	for _, risk := range risks {
		if risk.Component == component || risk.Component == "" {
			filtered = append(filtered, risk)
		}
	}
	return filtered
}

func filterChanges(changes []resultview.ChangeGroup, component reconciler.ComponentID) []resultview.ChangeGroup {
	if component == "" {
		return changes
	}
	var filtered []resultview.ChangeGroup
	for _, group := range changes {
		if group.Component == component {
			filtered = append(filtered, group)
		}
	}
	return filtered
}

func riskLine(risk resultview.Risk, width int) string {
	switch risk.Kind {
	case resultview.RiskConflict:
		return truncateMiddle(fmt.Sprintf("Conflict · %s · %s", risk.Path, risk.Summary), width)
	case resultview.RiskRetirement:
		return truncateMiddle(fmt.Sprintf("Retirement · %s", risk.Path), width)
	case resultview.RiskBlocker:
		return truncateMiddle(fmt.Sprintf("%s · %s", risk.BlockerCode, risk.Summary), width)
	default:
		return truncateMiddle("System Change · "+risk.Summary, width)
	}
}

func progressLine(event reconciler.ProgressEvent, width int) string {
	subject := event.Operation
	if event.Kind == reconciler.ProgressComponent {
		subject = string(event.Component)
	}
	if event.Kind == reconciler.ProgressChange {
		subject = string(event.ChangeKind)
		if event.Component != "" {
			subject = string(event.Component) + " · " + subject
		}
	}
	line := fmt.Sprintf("%s  %s", statusGlyph(string(event.Status)), subject)
	if event.Path != "" {
		line += "  " + event.Path
	}
	if event.Summary != "" {
		line += "  " + event.Summary
	}
	return truncateMiddle(line, width)
}

func truncateMiddle(value string, width int) string {
	if width <= 0 || lipgloss.Width(value) <= width {
		return value
	}
	if width < 5 {
		return strings.Repeat("…", max(0, width))
	}
	runes := []rune(value)
	left := width / 2
	right := width - left - 1
	if left+right >= len(runes) {
		return value
	}
	return string(runes[:left]) + "…" + string(runes[len(runes)-right:])
}

func joinComponentIDs(components []reconciler.ComponentID) string {
	parts := make([]string, 0, len(components))
	for _, component := range components {
		parts = append(parts, string(component))
	}
	return strings.Join(parts, ", ")
}

func max(left int, right int) int {
	if left > right {
		return left
	}
	return right
}

func min(left int, right int) int {
	if left < right {
		return left
	}
	return right
}

func visibleWindow(length int, cursor int, capacity int) (int, int) {
	if length <= capacity {
		return 0, length
	}
	start := cursor - capacity/2
	if start < 0 {
		start = 0
	}
	if start+capacity > length {
		start = length - capacity
	}
	return start, start + capacity
}
