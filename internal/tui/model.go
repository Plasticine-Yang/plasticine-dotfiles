package tui

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/resultview"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/workstation"
)

type screen int

const (
	screenDashboard screen = iota
	screenPlan
	screenComponents
	screenDoctor
)

type dialog int

const (
	dialogNone dialog = iota
	dialogHelp
	dialogDiscard
	dialogAuthorization
	dialogGitHubKey
	dialogTerminal
)

type selectionColumn int

const (
	columnScope selectionColumn = iota
	columnRun
)

type authItem struct {
	label   string
	checked bool
	kind    string
}

type model struct {
	runtime workstation.Runtime
	bridge  *operationBridge
	theme   theme

	width  int
	height int
	screen screen
	dialog dialog

	viewport viewport.Model
	keyInput textinput.Model

	catalog         []reconciler.ComponentDefinition
	planCursor      int
	componentCursor int
	column          selectionColumn
	detailFocused   bool

	scopeExcluded  map[reconciler.ComponentID]bool
	scopeKnown     bool
	scopeDirty     bool
	scopeReviewed  bool
	filterSelected map[reconciler.ComponentID]bool
	skipLoginShell bool
	adoptConflicts bool

	operation        string
	operationCancel  bool
	interruptPending bool
	exitReason       ExitReason
	status           string
	err              error

	planResult   *reconciler.Result
	doctorResult *reconciler.Result
	latestResult *reconciler.Result

	progressLog   []reconciler.ProgressEvent
	currentChange *reconciler.ProgressEvent

	authResult     reconciler.Result
	authResponse   chan<- reconciler.AuthorizationDecision
	authItems      []authItem
	authCursor     int
	authRiskOffset int
	keyResponse    chan<- keySelection
}

func newModel(runtime workstation.Runtime, env map[string]string, bridge *operationBridge) model {
	catalog := reconciler.ComponentCatalog()
	filterSelected := make(map[reconciler.ComponentID]bool, len(catalog))
	for _, component := range catalog {
		filterSelected[component.ID] = true
	}
	input := textinput.New()
	input.Prompt = ""
	input.Placeholder = "/Users/owner/.ssh/id_ed25519"
	input.CharLimit = 4096
	input.Width = 54
	return model{
		runtime:         runtime,
		bridge:          bridge,
		theme:           newTheme(env),
		screen:          screenDashboard,
		viewport:        viewport.New(80, 20),
		keyInput:        input,
		catalog:         catalog,
		scopeExcluded:   map[reconciler.ComponentID]bool{},
		filterSelected:  filterSelected,
		exitReason:      ExitOwnerQuit,
		status:          "Ready",
		componentCursor: 0,
	}
}

func (m model) Init() tea.Cmd {
	return textinput.Blink
}

func (m model) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch message := message.(type) {
	case tea.WindowSizeMsg:
		m.width = message.Width
		m.height = message.Height
		m.resizeViewport()
		return m, nil
	case progressMsg:
		event := reconciler.ProgressEvent(message)
		m.appendProgress(event)
		return m, nil
	case operationDoneMsg:
		m.operation = ""
		m.operationCancel = false
		m.err = message.err
		if message.err != nil {
			if m.interruptPending && errors.Is(message.err, context.Canceled) {
				return m, tea.Quit
			}
			m.status = message.operation + " failed"
		} else {
			result := message.result
			m.latestResult = &result
			m.status = message.operation + " " + string(result.Outcome)
			switch message.operation {
			case "plan":
				m.planResult = &result
				m.screen = screenPlan
				if scopeObservable(result.Scope) {
					if m.scopeDirty {
						m.scopeReviewed = true
					} else {
						m.loadScope(result.Scope.Excluded)
					}
				} else if m.scopeDirty {
					m.scopeReviewed = false
					m.status = "Plan could not validate the Workstation Scope draft"
				}
			case "apply":
				m.planResult = &result
				m.screen = screenPlan
				if result.Outcome == reconciler.OutcomeApplied || result.Outcome == reconciler.OutcomeNoChange {
					m.loadScope(result.Scope.Excluded)
					m.scopeDirty = false
					m.scopeReviewed = false
				}
			case "doctor":
				m.doctorResult = &result
				m.screen = screenDoctor
			}
		}
		if m.interruptPending {
			return m, tea.Quit
		}
		return m, nil
	case authorizationRequestMsg:
		m.dialog = dialogAuthorization
		m.authResult = message.result
		m.authResponse = message.response
		m.authItems = authorizationItems(message.result, m.adoptConflicts)
		m.authCursor = 0
		m.authRiskOffset = 0
		return m, nil
	case keyRequestMsg:
		m.dialog = dialogGitHubKey
		m.keyResponse = message.response
		m.keyInput.SetValue("")
		return m, m.keyInput.Focus()
	case terminalRequestMsg:
		m.dialog = dialogTerminal
		command := exec.CommandContext(message.ctx, message.command.Name, message.command.Args...)
		return m, tea.ExecProcess(command, func(err error) tea.Msg {
			return terminalDoneMsg{
				response:    message.response,
				err:         err,
				interrupted: terminalInterrupted(err),
			}
		})
	case terminalDoneMsg:
		m.dialog = dialogNone
		responseErr := message.err
		if message.interrupted {
			m.exitReason = ExitInterrupted
			m.interruptPending = true
			m.operationCancel = true
			m.bridge.cancelOperation()
			responseErr = context.Canceled
		}
		select {
		case message.response <- responseErr:
		default:
		}
		return m, nil
	}

	if m.width > 0 && (m.width < 60 || m.height < 18) {
		if key, ok := message.(tea.KeyMsg); ok && key.String() == "ctrl+c" {
			m.exitReason = ExitInterrupted
			return m, tea.Quit
		}
		return m, nil
	}

	if m.dialog != dialogNone {
		return m.updateDialog(message)
	}

	if key, ok := message.(tea.KeyMsg); ok {
		if command := m.updateGlobalKey(key); command != nil {
			return m, command
		}
	}

	if m.screen == screenComponents {
		return m.updateComponents(message)
	}
	if m.screen == screenPlan {
		if key, ok := message.(tea.KeyMsg); ok {
			rows := 1
			if m.planResult != nil {
				rows += len(planComponents(*m.planResult))
			}
			switch key.String() {
			case "up", "k":
				if m.width < 100 && m.detailFocused {
					break
				}
				if m.planCursor > 0 {
					m.planCursor--
					m.viewport.GotoTop()
					m.syncViewportContent()
				}
				return m, nil
			case "down", "j":
				if m.width < 100 && m.detailFocused {
					break
				}
				if m.planCursor < rows-1 {
					m.planCursor++
					m.viewport.GotoTop()
					m.syncViewportContent()
				}
				return m, nil
			case "enter":
				if m.width < 100 {
					m.detailFocused = !m.detailFocused
					m.viewport.GotoTop()
				}
				return m, nil
			}
		}
	}
	m.syncViewportContent()
	var command tea.Cmd
	m.viewport, command = m.viewport.Update(message)
	return m, command
}

func (m *model) updateGlobalKey(key tea.KeyMsg) tea.Cmd {
	switch key.String() {
	case "ctrl+c":
		m.exitReason = ExitInterrupted
		if m.operation != "" {
			m.interruptPending = true
			m.operationCancel = true
			m.status = "Canceling " + m.operation + " safely..."
			m.bridge.cancelOperation()
			return nil
		}
		return tea.Quit
	case "q":
		if m.operation != "" {
			m.status = m.operation + " is active; use Ctrl-C for safe cancellation"
			return nil
		}
		if m.scopeDirty {
			m.dialog = dialogDiscard
			return nil
		}
		m.exitReason = ExitOwnerQuit
		return tea.Quit
	case "?":
		m.dialog = dialogHelp
		return nil
	case "1":
		m.screen = screenDashboard
		m.detailFocused = false
		m.viewport.GotoTop()
	case "2":
		m.screen = screenPlan
		m.detailFocused = false
		m.viewport.GotoTop()
	case "3":
		m.screen = screenComponents
		m.detailFocused = false
		m.viewport.GotoTop()
	case "4":
		m.screen = screenDoctor
		m.detailFocused = false
		m.viewport.GotoTop()
	case "p":
		m.startPlan()
	case "a":
		m.startApply()
	case "d":
		m.startDoctor()
	case "tab":
		if m.screen == screenPlan {
			m.detailFocused = !m.detailFocused
			m.viewport.GotoTop()
		}
	}
	return nil
}

func (m model) updateDialog(message tea.Msg) (tea.Model, tea.Cmd) {
	key, isKey := message.(tea.KeyMsg)
	switch m.dialog {
	case dialogHelp:
		if isKey && (key.String() == "?" || key.String() == "esc" || key.String() == "enter") {
			m.dialog = dialogNone
		}
		return m, nil
	case dialogDiscard:
		if !isKey {
			return m, nil
		}
		switch key.String() {
		case "y", "Y", "enter":
			m.exitReason = ExitOwnerQuit
			return m, tea.Quit
		case "n", "N", "esc":
			m.dialog = dialogNone
		}
		return m, nil
	case dialogAuthorization:
		if mouse, ok := message.(tea.MouseMsg); ok && mouse.Action == tea.MouseActionPress {
			switch mouse.Button {
			case tea.MouseButtonWheelUp:
				m.shiftAuthorizationRisks(-2)
			case tea.MouseButtonWheelDown:
				m.shiftAuthorizationRisks(2)
			}
			return m, nil
		}
		if !isKey {
			return m, nil
		}
		switch key.String() {
		case "ctrl+c":
			m.exitReason = ExitInterrupted
			m.interruptPending = true
			m.operationCancel = true
			m.bridge.cancelOperation()
			m.dialog = dialogNone
		case "esc", "n", "N":
			m.respondAuthorization(reconciler.AuthorizationDecision{})
		case "up", "k":
			if m.authCursor > 0 {
				m.authCursor--
			}
		case "down", "j", "tab":
			if m.authCursor < len(m.authItems)-1 {
				m.authCursor++
			}
		case "pgup", "ctrl+u":
			m.shiftAuthorizationRisks(-5)
		case "pgdown", "ctrl+d":
			m.shiftAuthorizationRisks(5)
		case " ":
			if len(m.authItems) > 0 {
				m.authItems[m.authCursor].checked = !m.authItems[m.authCursor].checked
			}
		case "enter", "y", "Y":
			if m.authorizationComplete() {
				m.respondAuthorization(m.authorizationDecision())
			} else {
				m.status = "Check every required authorization"
			}
		}
		return m, nil
	case dialogGitHubKey:
		if isKey {
			switch key.String() {
			case "ctrl+c":
				m.exitReason = ExitInterrupted
				m.interruptPending = true
				m.operationCancel = true
				m.bridge.cancelOperation()
				m.dialog = dialogNone
				return m, nil
			case "esc":
				m.respondKey(keySelection{})
				return m, nil
			case "enter":
				path := strings.TrimSpace(m.keyInput.Value())
				if path == "" {
					m.status = "Enter an absolute private-key path or press Esc"
					return m, nil
				}
				m.respondKey(keySelection{path: path, selected: true})
				return m, nil
			}
		}
		var command tea.Cmd
		m.keyInput, command = m.keyInput.Update(message)
		return m, command
	case dialogTerminal:
		if isKey && key.String() == "ctrl+c" {
			m.exitReason = ExitInterrupted
			m.interruptPending = true
			m.operationCancel = true
			m.bridge.cancelOperation()
		}
		return m, nil
	default:
		return m, nil
	}
}

func (m model) updateComponents(message tea.Msg) (tea.Model, tea.Cmd) {
	key, ok := message.(tea.KeyMsg)
	if !ok {
		var command tea.Cmd
		m.viewport, command = m.viewport.Update(message)
		return m, command
	}
	rowCount := len(m.catalog) + 2
	switch key.String() {
	case "up", "k":
		if m.componentCursor > 0 {
			m.componentCursor--
		}
	case "down", "j":
		if m.componentCursor < rowCount-1 {
			m.componentCursor++
		}
	case "tab":
		if m.componentCursor < len(m.catalog) {
			if m.column == columnScope {
				m.column = columnRun
			} else {
				m.column = columnScope
			}
		}
	case "enter", " ":
		m.toggleComponentRow()
	}
	return m, nil
}

func (m *model) toggleComponentRow() {
	if m.operation != "" {
		m.status = "Wait for the current operation"
		return
	}
	if m.componentCursor < len(m.catalog) {
		component := m.catalog[m.componentCursor].ID
		if m.column == columnScope {
			if !m.scopeKnown {
				m.status = "Run Plan first to load the current Workstation Scope"
				return
			}
			m.scopeExcluded[component] = !m.scopeExcluded[component]
			m.scopeDirty = true
			m.scopeReviewed = false
			m.status = "Workstation Scope draft changed; run Plan before Apply"
		} else {
			m.filterSelected[component] = !m.filterSelected[component]
			m.status = "One-run Component filter changed"
		}
		return
	}
	switch m.componentCursor - len(m.catalog) {
	case 0:
		m.skipLoginShell = !m.skipLoginShell
		m.status = "skip-login-shell changed for this session"
	case 1:
		m.adoptConflicts = !m.adoptConflicts
		m.status = "adoption intent changed for this session"
	}
}

func (m *model) startPlan() {
	if m.operation != "" {
		return
	}
	m.screen = screenPlan
	m.operation = "plan"
	m.err = nil
	m.status = "Planning..."
	m.progressLog = nil
	m.currentChange = nil
	request := m.operationRequest()
	request.GitHubKeySelector = m.bridge.selectGitHubKey
	request.Progress = func(event reconciler.ProgressEvent) {
		m.bridge.send(progressMsg(event))
	}
	m.bridge.start("plan", func(ctx context.Context) (reconciler.Result, error) {
		return m.runtime.Reconciler.Plan(ctx, request)
	})
}

func (m *model) startApply() {
	if m.operation != "" {
		return
	}
	if m.scopeDirty && !m.scopeReviewed {
		m.screen = screenComponents
		m.status = "Run Plan to review the Workstation Scope draft before Apply"
		return
	}
	m.screen = screenPlan
	m.operation = "apply"
	m.err = nil
	m.status = "Building the exact Apply plan..."
	m.progressLog = nil
	m.currentChange = nil
	request := m.operationRequest()
	request.Authorize = m.bridge.authorize
	request.GitHubKeySelector = m.bridge.selectGitHubKey
	request.TerminalRunner = m.bridge.runTerminal
	request.InstallerStdout = m.bridge.out
	request.InstallerStderr = m.bridge.err
	request.Progress = func(event reconciler.ProgressEvent) {
		m.bridge.send(progressMsg(event))
	}
	m.bridge.start("apply", func(ctx context.Context) (reconciler.Result, error) {
		return m.runtime.Reconciler.Apply(ctx, request)
	})
}

func (m *model) startDoctor() {
	if m.operation != "" {
		return
	}
	m.screen = screenDoctor
	m.operation = "doctor"
	m.err = nil
	m.status = "Running Doctor..."
	m.progressLog = nil
	m.currentChange = nil
	request := m.operationRequest()
	request.Progress = func(event reconciler.ProgressEvent) {
		m.bridge.send(progressMsg(event))
	}
	m.bridge.start("doctor", func(ctx context.Context) (reconciler.Result, error) {
		return m.runtime.Reconciler.Doctor(ctx, request)
	})
}

func (m model) operationRequest() reconciler.Request {
	request := m.runtime.Request()
	request.SkipLoginShell = m.skipLoginShell
	request.Adopt = m.adoptConflicts
	if m.scopeKnown || m.scopeDirty {
		request.ReplaceScope = true
		request.Exclude = m.excludedComponents()
	}
	request.Components = m.filteredComponents()
	return request
}

func (m model) excludedComponents() []reconciler.ComponentID {
	var excluded []reconciler.ComponentID
	for _, component := range m.catalog {
		if m.scopeExcluded[component.ID] {
			excluded = append(excluded, component.ID)
		}
	}
	return excluded
}

func (m model) filteredComponents() []reconciler.ComponentID {
	if len(m.filterSelected) == 0 {
		return nil
	}
	var selected []reconciler.ComponentID
	for _, component := range m.catalog {
		if m.filterSelected[component.ID] {
			selected = append(selected, component.ID)
		}
	}
	if len(selected) == len(m.catalog) {
		return nil
	}
	if len(selected) == 0 {
		return []reconciler.ComponentID{"__no-components-selected__"}
	}
	return selected
}

func (m *model) loadScope(excluded []reconciler.ComponentID) {
	m.scopeExcluded = map[reconciler.ComponentID]bool{}
	for _, component := range excluded {
		m.scopeExcluded[component] = true
	}
	m.scopeKnown = true
}

func scopeObservable(scope reconciler.ScopeSummary) bool {
	return len(scope.Active)+len(scope.Excluded)+len(scope.Suspended) > 0
}

func (m *model) appendProgress(event reconciler.ProgressEvent) {
	const maxEvents = 200
	m.progressLog = append(m.progressLog, event)
	if len(m.progressLog) > maxEvents {
		m.progressLog = append([]reconciler.ProgressEvent(nil), m.progressLog[len(m.progressLog)-maxEvents:]...)
	}
	if event.Kind == reconciler.ProgressChange && event.Status == reconciler.ProgressStarted {
		copy := event
		m.currentChange = &copy
	}
	if event.Kind == reconciler.ProgressChange && event.Status != reconciler.ProgressStarted {
		m.currentChange = nil
	}
	m.syncViewportContent()
	m.viewport.GotoBottom()
}

func (m *model) resizeViewport() {
	width := m.width - 6
	if width < 20 {
		width = 20
	}
	height := m.height - 8
	if height < 5 {
		height = 5
	}
	m.viewport.Width = width
	m.viewport.Height = height
	m.syncViewportContent()
}

func (m *model) syncViewportContent() {
	width := max(20, m.viewport.Width)
	switch {
	case (m.operation == "apply" || m.operation == "plan" || m.operation == "doctor") && len(m.progressLog) > 0:
		m.viewport.SetContent(m.progressContent(width))
	case m.screen == screenPlan && m.planResult != nil:
		m.viewport.SetContent(m.planDetailContent(resultview.Project("plan", *m.planResult), width))
	case m.screen == screenDoctor && m.doctorResult != nil:
		m.viewport.SetContent(m.doctorContent(resultview.Project("doctor", *m.doctorResult)))
	default:
		m.viewport.SetContent("")
	}
}

func (m *model) respondAuthorization(decision reconciler.AuthorizationDecision) {
	response := m.authResponse
	m.authResponse = nil
	m.dialog = dialogNone
	select {
	case response <- decision:
	default:
	}
}

func (m *model) respondKey(selection keySelection) {
	response := m.keyResponse
	m.keyResponse = nil
	m.keyInput.Blur()
	m.dialog = dialogNone
	select {
	case response <- selection:
	default:
	}
}

func authorizationItems(result reconciler.Result, adoptionIntent bool) []authItem {
	items := []authItem{{label: "Apply the exact reviewed plan", kind: "ordinary"}}
	if resultHasSystemChanges(result) {
		items = append(items, authItem{label: "Allow listed System Changes", kind: "system"})
	}
	if adoptionIntent && hasAdoptableConflicts(result.Conflicts) {
		items = append(items, authItem{label: "Back up and adopt listed Conflicts", kind: "adoption"})
	}
	if len(result.Retirements) > 0 {
		items = append(items, authItem{label: "Delete listed retired managed resources", kind: "retirement"})
	}
	return items
}

func (m model) authorizationComplete() bool {
	for _, item := range m.authItems {
		if !item.checked {
			return false
		}
	}
	return len(m.authItems) > 0
}

func (m model) authorizationDecision() reconciler.AuthorizationDecision {
	decision := reconciler.AuthorizationDecision{}
	for _, item := range m.authItems {
		switch item.kind {
		case "ordinary":
			decision.Approved = item.checked
		case "system":
			decision.AllowSystemChanges = item.checked
		case "adoption":
			decision.AllowAdoption = item.checked
		case "retirement":
			decision.AllowRetirements = item.checked
		}
	}
	return decision
}

func (m *model) shiftAuthorizationRisks(delta int) {
	riskCount := len(authorizationRiskLines(m.authResult, max(1, m.width-12)))
	pageSize := max(1, m.height-len(m.authItems)-13)
	maxOffset := max(0, riskCount-pageSize)
	m.authRiskOffset = min(maxOffset, max(0, m.authRiskOffset+delta))
}

func resultHasSystemChanges(result reconciler.Result) bool {
	for _, change := range result.Changes {
		if change.SystemChange {
			return true
		}
	}
	return false
}

func hasAdoptableConflicts(conflicts []reconciler.Conflict) bool {
	for _, conflict := range conflicts {
		if conflict.Adoptable {
			return true
		}
	}
	return false
}

func (m model) validationMessages() []string {
	var messages []string
	scopeActive := func(component reconciler.ComponentID) bool {
		return !m.scopeExcluded[component]
	}
	filterActive := func(component reconciler.ComponentID) bool {
		return m.filterSelected[component]
	}
	for _, definition := range m.catalog {
		for _, dependency := range definition.Dependencies {
			if scopeActive(definition.ID) && !scopeActive(dependency) {
				messages = append(messages, fmt.Sprintf("Scope: %s requires active %s", definition.ID, dependency))
			}
			if filterActive(definition.ID) && !filterActive(dependency) {
				messages = append(messages, fmt.Sprintf("Run filter: %s requires selected %s", definition.ID, dependency))
			}
		}
	}
	if noComponentsSelected(m.catalog, m.filterSelected) {
		messages = append(messages, "Run filter: select at least one Component")
	}
	sort.Strings(messages)
	return messages
}

func allComponentsSelected(catalog []reconciler.ComponentDefinition, selected map[reconciler.ComponentID]bool) bool {
	for _, component := range catalog {
		if !selected[component.ID] {
			return false
		}
	}
	return true
}

func noComponentsSelected(catalog []reconciler.ComponentDefinition, selected map[reconciler.ComponentID]bool) bool {
	for _, component := range catalog {
		if selected[component.ID] {
			return false
		}
	}
	return true
}
