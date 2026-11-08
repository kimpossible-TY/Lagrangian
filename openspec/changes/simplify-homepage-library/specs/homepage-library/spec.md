## Purpose

Provide a focused, accessible Homepage for selecting and opening configured documents and managing Reader settings.

## ADDED Requirements

### Requirement: Searchable document library
The Homepage SHALL show document names, actual states, count and search, with one safe primary opening link and all other safe variants as alternatives.

#### Scenario: Preferred destination
- **WHEN** a document has a safe HTML URL
- **THEN** its primary 열기 link uses that URL; otherwise it uses a safe Paged URL if available

#### Scenario: Inventory polling
- **WHEN** polling retains a valid reader link
- **THEN** its DOM identity and keyboard focus remain stable; if the focused destination is removed, focus moves to the documents section

### Requirement: Accessible Homepage settings
The Homepage SHALL place appearance, account and service information in a named native dialog while preserving existing authentication authority and explicit action requirements.

#### Scenario: Open and close settings
- **WHEN** settings is opened by keyboard and closed with Escape or its close button
- **THEN** focus returns to the invoking control and the dialog remains scrollable on mobile

#### Scenario: Account link
- **WHEN** the Homepage initially loads with `#connection` or receives that hash through a hashchange
- **THEN** settings opens at the account area

#### Scenario: Appearance
- **WHEN** the user chooses 화면 모드
- **THEN** the existing shared theme preference offers system, light and dark
