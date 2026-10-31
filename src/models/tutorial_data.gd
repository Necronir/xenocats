class_name TutorialData
extends Resource

## TutorialData: Ресурс контекстной подсказки обучения (ADR-001 Section 2.5, Issue #12)

enum Presentation {
	MODAL,
	TOAST
}

@export var tutorial_id: StringName = &""
@export var title: String = ""
@export_multiline var body: String = ""
@export var order: int = 0
@export var presentation: Presentation = Presentation.MODAL
@export var toast_duration: float = 7.0

