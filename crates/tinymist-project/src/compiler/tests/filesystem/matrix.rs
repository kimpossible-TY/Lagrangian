//! Runtime-facing filesystem event dimensions, rows and documented omissions.

use super::MockChange;
use super::ProjectCompilerHarness;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum OperationId {
    O01,
    O02,
    O03,
    O04,
    O05,
    O06,
    O07,
    O08,
    O09,
    O10,
    O11,
    O12,
    O13,
    O14,
    O15,
    O16,
    O17,
    O18,
    O19,
    O20,
}

impl OperationId {
    pub(super) fn label(self) -> &'static str {
        match self {
            OperationId::O01 => "O01",
            OperationId::O02 => "O02",
            OperationId::O03 => "O03",
            OperationId::O04 => "O04",
            OperationId::O05 => "O05",
            OperationId::O06 => "O06",
            OperationId::O07 => "O07",
            OperationId::O08 => "O08",
            OperationId::O09 => "O09",
            OperationId::O10 => "O10",
            OperationId::O11 => "O11",
            OperationId::O12 => "O12",
            OperationId::O13 => "O13",
            OperationId::O14 => "O14",
            OperationId::O15 => "O15",
            OperationId::O16 => "O16",
            OperationId::O17 => "O17",
            OperationId::O18 => "O18",
            OperationId::O19 => "O19",
            OperationId::O20 => "O20",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum MatrixOperation {
    InitialSync,
    FollowUpNonSyncUpdate,
    CreateDependency,
    EditEntry,
    EditDependency,
    CreateUnrelated,
    RemoveDependency,
    ReadErrorDependency,
    EmptyDependency,
    EmptyUnrelated,
    RenameUpdatedReferences,
    RenameStaleReferences,
    DeleteThenRecreate,
    FailedReadThenRecovery,
    RenameBatch,
    MultiFileUnrelatedBatch,
    UpstreamInvalidation,
    UnrelatedChurn,
    EmptyChangeset,
    DependencyMembershipRemoval,
    DependencyMembershipReaddition,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum EventVariant {
    Update,
    UpstreamUpdate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum SyncMode {
    Sync,
    NonSync,
    NotApplicable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum InsertPayload {
    NonEmptyContent,
    EmptyContent,
    ReadErrorSnapshot,
    NoInserts,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum RemovePayload {
    NoRemoves,
    OneRemovedPath,
    MultipleRemovedPaths,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PathRelation {
    EntryFile,
    ImportedDependency,
    PreviouslyDependedPath,
    NewlyCreatedDependency,
    NewlyReferencedDependency,
    RetainedInactiveDependency,
    UnrelatedFile,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum BatchShape {
    InsertOnly,
    RemoveOnly,
    RemovePlusInsert,
    MultiFileBatch,
    EmptyChangeset,
    RemoveOnlyThenInsertOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum SequenceShape {
    InitialSync,
    OneStepEdit,
    CreateAfterMissingImport,
    OneStepRemove,
    RenameOldPlusNew,
    FailedRead,
    FailedReadThenRecovery,
    TransientEmptyWrite,
    DeleteThenRecreate,
    DelayedMemoryThenFilesystem,
    EmptyChangeset,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ExpectedOutcome {
    IgnoredFirstSync,
    FsReasonRefreshesDependency,
    RecoversNewDependency,
    RefreshesEntrySource,
    RefreshesDependencySource,
    KeepsUnrelatedCreateHarmless,
    ReportsRetiredDependencyUnavailable,
    SurfacesReadErrorDiagnostics,
    UsesEmptyDependencySnapshot,
    KeepsEmptyUnrelatedHarmless,
    FollowsRenamedPath,
    ReportsOldImportUnavailable,
    ReportsThenRecoversRecreatedSource,
    ClearsDiagnosticsAfterRecovery,
    RenameBatchFollowsRenamedPath,
    MultiFileUnrelatedBatchHarmless,
    AppliesDelayedMemoryBeforeFilesystem,
    KeepsUnrelatedChurnHarmless,
    ExplicitNoContentOutcome,
    DropsInactiveDependency,
    ReaddsChangedInactiveDependency,
}

#[derive(Debug, Clone, Copy)]
pub(super) struct MatrixRow {
    pub(super) operation: MatrixOperation,
    pub(super) event_variant: EventVariant,
    pub(super) sync_mode: SyncMode,
    pub(super) insert_payload: InsertPayload,
    pub(super) remove_payload: RemovePayload,
    pub(super) path_relations: &'static [PathRelation],
    pub(super) batch_shape: BatchShape,
    pub(super) sequence_shape: SequenceShape,
    pub(super) expected: ExpectedOutcome,
}

#[derive(Debug, Clone, Copy)]
pub(super) struct CompileCacheCoverageRow {
    pub(super) id: OperationId,
    pub(super) matrix_operations: &'static [MatrixOperation],
    pub(super) note: &'static str,
}

impl MatrixRow {
    pub(super) fn sync_bool(self) -> bool {
        match self.sync_mode {
            SyncMode::Sync => true,
            SyncMode::NonSync => false,
            SyncMode::NotApplicable => {
                panic!(
                    "matrix row {:?} does not carry an update sync flag",
                    self.operation
                )
            }
        }
    }

    pub(super) fn apply_update(self, harness: &mut ProjectCompilerHarness, change: &MockChange) {
        assert_eq!(self.event_variant, EventVariant::Update);
        harness.apply_update(change, self.sync_bool());
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum OmittedEventCombination {
    SyncFlagOnUpstreamUpdate,
    EntryFileReadErrorAfterDirectClientInput,
    BackendSpecificNotifyRenameQuirk,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum OmissionReason {
    Unreachable,
    Redundant,
    Deferred,
}

#[derive(Debug)]
pub(super) struct OmittedCombination {
    pub(super) combination: OmittedEventCombination,
    pub(super) reason: OmissionReason,
}

pub(super) const PROJECT_COMPILER_FS_EVENT_MATRIX: &[MatrixRow] = &[
    MatrixRow {
        operation: MatrixOperation::InitialSync,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::Sync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::EntryFile, PathRelation::ImportedDependency],
        batch_shape: BatchShape::MultiFileBatch,
        sequence_shape: SequenceShape::InitialSync,
        expected: ExpectedOutcome::IgnoredFirstSync,
    },
    MatrixRow {
        operation: MatrixOperation::FollowUpNonSyncUpdate,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::ImportedDependency],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::FsReasonRefreshesDependency,
    },
    MatrixRow {
        operation: MatrixOperation::CreateDependency,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::NewlyCreatedDependency],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::CreateAfterMissingImport,
        expected: ExpectedOutcome::RecoversNewDependency,
    },
    MatrixRow {
        operation: MatrixOperation::EditEntry,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::EntryFile],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::RefreshesEntrySource,
    },
    MatrixRow {
        operation: MatrixOperation::EditDependency,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::ImportedDependency],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::RefreshesDependencySource,
    },
    MatrixRow {
        operation: MatrixOperation::CreateUnrelated,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::UnrelatedFile],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::KeepsUnrelatedCreateHarmless,
    },
    MatrixRow {
        operation: MatrixOperation::RemoveDependency,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NoInserts,
        remove_payload: RemovePayload::OneRemovedPath,
        path_relations: &[PathRelation::PreviouslyDependedPath],
        batch_shape: BatchShape::RemoveOnly,
        sequence_shape: SequenceShape::OneStepRemove,
        expected: ExpectedOutcome::ReportsRetiredDependencyUnavailable,
    },
    MatrixRow {
        operation: MatrixOperation::ReadErrorDependency,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::ReadErrorSnapshot,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::ImportedDependency],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::FailedRead,
        expected: ExpectedOutcome::SurfacesReadErrorDiagnostics,
    },
    MatrixRow {
        operation: MatrixOperation::EmptyDependency,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::EmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::ImportedDependency],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::TransientEmptyWrite,
        expected: ExpectedOutcome::UsesEmptyDependencySnapshot,
    },
    MatrixRow {
        operation: MatrixOperation::EmptyUnrelated,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::EmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::UnrelatedFile],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::TransientEmptyWrite,
        expected: ExpectedOutcome::KeepsEmptyUnrelatedHarmless,
    },
    MatrixRow {
        operation: MatrixOperation::RenameUpdatedReferences,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::OneRemovedPath,
        path_relations: &[
            PathRelation::PreviouslyDependedPath,
            PathRelation::NewlyReferencedDependency,
        ],
        batch_shape: BatchShape::RemovePlusInsert,
        sequence_shape: SequenceShape::RenameOldPlusNew,
        expected: ExpectedOutcome::FollowsRenamedPath,
    },
    MatrixRow {
        operation: MatrixOperation::RenameStaleReferences,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::OneRemovedPath,
        path_relations: &[PathRelation::PreviouslyDependedPath],
        batch_shape: BatchShape::RemovePlusInsert,
        sequence_shape: SequenceShape::RenameOldPlusNew,
        expected: ExpectedOutcome::ReportsOldImportUnavailable,
    },
    MatrixRow {
        operation: MatrixOperation::DeleteThenRecreate,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::OneRemovedPath,
        path_relations: &[PathRelation::PreviouslyDependedPath],
        batch_shape: BatchShape::RemoveOnlyThenInsertOnly,
        sequence_shape: SequenceShape::DeleteThenRecreate,
        expected: ExpectedOutcome::ReportsThenRecoversRecreatedSource,
    },
    MatrixRow {
        operation: MatrixOperation::FailedReadThenRecovery,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::ImportedDependency],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::FailedReadThenRecovery,
        expected: ExpectedOutcome::ClearsDiagnosticsAfterRecovery,
    },
    MatrixRow {
        operation: MatrixOperation::RenameBatch,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::OneRemovedPath,
        path_relations: &[
            PathRelation::PreviouslyDependedPath,
            PathRelation::NewlyReferencedDependency,
        ],
        batch_shape: BatchShape::RemovePlusInsert,
        sequence_shape: SequenceShape::RenameOldPlusNew,
        expected: ExpectedOutcome::RenameBatchFollowsRenamedPath,
    },
    MatrixRow {
        operation: MatrixOperation::MultiFileUnrelatedBatch,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::MultipleRemovedPaths,
        path_relations: &[PathRelation::UnrelatedFile],
        batch_shape: BatchShape::MultiFileBatch,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::MultiFileUnrelatedBatchHarmless,
    },
    MatrixRow {
        operation: MatrixOperation::UpstreamInvalidation,
        event_variant: EventVariant::UpstreamUpdate,
        sync_mode: SyncMode::NotApplicable,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::EntryFile],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::DelayedMemoryThenFilesystem,
        expected: ExpectedOutcome::AppliesDelayedMemoryBeforeFilesystem,
    },
    MatrixRow {
        operation: MatrixOperation::UnrelatedChurn,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::UnrelatedFile],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::KeepsUnrelatedChurnHarmless,
    },
    MatrixRow {
        operation: MatrixOperation::EmptyChangeset,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NoInserts,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[PathRelation::UnrelatedFile],
        batch_shape: BatchShape::EmptyChangeset,
        sequence_shape: SequenceShape::EmptyChangeset,
        expected: ExpectedOutcome::ExplicitNoContentOutcome,
    },
    MatrixRow {
        operation: MatrixOperation::DependencyMembershipRemoval,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[
            PathRelation::EntryFile,
            PathRelation::RetainedInactiveDependency,
        ],
        batch_shape: BatchShape::InsertOnly,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::DropsInactiveDependency,
    },
    MatrixRow {
        operation: MatrixOperation::DependencyMembershipReaddition,
        event_variant: EventVariant::Update,
        sync_mode: SyncMode::NonSync,
        insert_payload: InsertPayload::NonEmptyContent,
        remove_payload: RemovePayload::NoRemoves,
        path_relations: &[
            PathRelation::EntryFile,
            PathRelation::RetainedInactiveDependency,
            PathRelation::ImportedDependency,
        ],
        batch_shape: BatchShape::MultiFileBatch,
        sequence_shape: SequenceShape::OneStepEdit,
        expected: ExpectedOutcome::ReaddsChangedInactiveDependency,
    },
];

pub(super) const VFS_OPERATION_COMPILE_CACHE_MATRIX: &[CompileCacheCoverageRow] = &[
    CompileCacheCoverageRow {
        id: OperationId::O01,
        matrix_operations: &[MatrixOperation::CreateDependency],
        note: "create recovers a missing dependency and refreshes compile dependencies",
    },
    CompileCacheCoverageRow {
        id: OperationId::O02,
        matrix_operations: &[MatrixOperation::EditEntry, MatrixOperation::EditDependency],
        note: "content updates are asserted for both entry and active dependency paths",
    },
    CompileCacheCoverageRow {
        id: OperationId::O03,
        matrix_operations: &[
            MatrixOperation::EmptyDependency,
            MatrixOperation::EmptyUnrelated,
        ],
        note: "transient empty snapshots surface for active paths and remain harmless for unrelated paths",
    },
    CompileCacheCoverageRow {
        id: OperationId::O04,
        matrix_operations: &[
            MatrixOperation::ReadErrorDependency,
            MatrixOperation::FailedReadThenRecovery,
        ],
        note: "read-error snapshots replace stale sources and later recover",
    },
    CompileCacheCoverageRow {
        id: OperationId::O05,
        matrix_operations: &[MatrixOperation::RemoveDependency],
        note: "remove retires a depended path from compile-visible state",
    },
    CompileCacheCoverageRow {
        id: OperationId::O06,
        matrix_operations: &[MatrixOperation::DeleteThenRecreate],
        note: "delete then recreate reports missing before recovering with new bytes",
    },
    CompileCacheCoverageRow {
        id: OperationId::O07,
        matrix_operations: &[MatrixOperation::EditDependency],
        note: "atomic replace normalizes to a final dependency insert at the project boundary",
    },
    CompileCacheCoverageRow {
        id: OperationId::O08,
        matrix_operations: &[MatrixOperation::RenameStaleReferences],
        note: "stale-reference rename reports the old dependency unavailable",
    },
    CompileCacheCoverageRow {
        id: OperationId::O09,
        matrix_operations: &[
            MatrixOperation::RenameUpdatedReferences,
            MatrixOperation::RenameBatch,
        ],
        note: "updated-reference rename follows the new path and drops the old dependency",
    },
    CompileCacheCoverageRow {
        id: OperationId::O10,
        matrix_operations: &[MatrixOperation::RenameUpdatedReferences],
        note: "case-only rename is compile-cache equivalent to an updated-reference file rename",
    },
    CompileCacheCoverageRow {
        id: OperationId::O11,
        matrix_operations: &[
            MatrixOperation::RemoveDependency,
            MatrixOperation::CreateDependency,
        ],
        note: "root-boundary file moves normalize to remove-only or create-only project deltas",
    },
    CompileCacheCoverageRow {
        id: OperationId::O12,
        matrix_operations: &[MatrixOperation::RenameStaleReferences],
        note: "stale directory-prefix rename shares the old-path retirement obligation",
    },
    CompileCacheCoverageRow {
        id: OperationId::O13,
        matrix_operations: &[MatrixOperation::RenameBatch],
        note: "updated directory-prefix rename shares the batch new-path dependency obligation",
    },
    CompileCacheCoverageRow {
        id: OperationId::O14,
        matrix_operations: &[MatrixOperation::RemoveDependency],
        note: "directory delete compiles as one or more depended-path removals",
    },
    CompileCacheCoverageRow {
        id: OperationId::O15,
        matrix_operations: &[
            MatrixOperation::RemoveDependency,
            MatrixOperation::CreateDependency,
        ],
        note: "root-boundary subtree moves combine moved-out removes and moved-in creates",
    },
    CompileCacheCoverageRow {
        id: OperationId::O16,
        matrix_operations: &[MatrixOperation::DependencyMembershipRemoval],
        note: "entry edits that drop imports must remove retained inactive paths from dependencies",
    },
    CompileCacheCoverageRow {
        id: OperationId::O17,
        matrix_operations: &[MatrixOperation::DependencyMembershipReaddition],
        note: "re-added dependencies must consume fresh sync snapshots after inactive changes",
    },
    CompileCacheCoverageRow {
        id: OperationId::O18,
        matrix_operations: &[MatrixOperation::UpstreamInvalidation],
        note: "shadow-open filesystem races use upstream invalidation ordering",
    },
    CompileCacheCoverageRow {
        id: OperationId::O19,
        matrix_operations: &[MatrixOperation::EditDependency],
        note: "symlink-like target changes normalize to changed observable dependency bytes",
    },
    CompileCacheCoverageRow {
        id: OperationId::O20,
        matrix_operations: &[
            MatrixOperation::RenameBatch,
            MatrixOperation::MultiFileUnrelatedBatch,
        ],
        note: "mixed batches assert final-state dependency correctness and harmless unrelated churn",
    },
];

pub(super) const OMITTED_PROJECT_COMPILER_FS_EVENT_COMBINATIONS: &[OmittedCombination] = &[
    OmittedCombination {
        combination: OmittedEventCombination::SyncFlagOnUpstreamUpdate,
        reason: OmissionReason::Unreachable,
    },
    OmittedCombination {
        combination: OmittedEventCombination::EntryFileReadErrorAfterDirectClientInput,
        reason: OmissionReason::Redundant,
    },
    OmittedCombination {
        combination: OmittedEventCombination::BackendSpecificNotifyRenameQuirk,
        reason: OmissionReason::Deferred,
    },
];
