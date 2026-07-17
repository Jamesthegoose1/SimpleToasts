--!strict

export type Severity = "success" | "info" | "warn" | "error" | "secondary"

export type Position = "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right"

export type SeverityTheme = {
	backgroundColor: Color3,
	accentColor: Color3,
	detailTextColor: Color3?,
	iconAssetId: string?,
	soundAssetId: string?,
}

export type Message = {
	severity: Severity,
	summary: string,
	detail: string?,
	life: number?,
	sticky: boolean?,
	closable: boolean?,
	position: Position?,
	id: string?,
	customTheme: SeverityTheme?,
	sound: string?,
	silent: boolean?,
	volume: number?,
}

export type Config = {
	defaultLife: number,
	defaultPosition: Position,
	defaultClosable: boolean,
	maxVisible: number,
	displayOrder: number,
	stacked: boolean,
	expandedCount: number,
	toastWidth: number,
	toastMinHeight: number,
	cornerRadius: number,
	padding: number,
	gap: number,
	backgroundTransparency: number,
	fontSize: number,
	fontFace: Font,
	animationDuration: number,
	animationEasing: Enum.EasingStyle,
	closeIconAssetId: string,
	soundEnabled: boolean,
	defaultVolume: number,
	themes: {
		[string]: SeverityTheme,
	},
}

return nil
