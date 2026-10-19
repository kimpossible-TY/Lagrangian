//! Filesystem event, dependency membership and diagnostic freshness regressions.

use super::*;

mod matrix;
use matrix::*;

fn assert_matrix_contains<T: std::fmt::Debug>(missing: T, predicate: impl Fn(&MatrixRow) -> bool) {
    assert!(
        PROJECT_COMPILER_FS_EVENT_MATRIX.iter().any(predicate),
        "project compiler filesystem event matrix missing {missing:?}"
    );
}

fn assert_compile_cache_matrix_contains(id: OperationId) {
    assert!(
        VFS_OPERATION_COMPILE_CACHE_MATRIX
            .iter()
            .any(|row| row.id == id),
        "project compiler compile-cache matrix missing {}",
        id.label()
    );
}

fn project_matrix_row(operation: MatrixOperation) -> MatrixRow {
    *PROJECT_COMPILER_FS_EVENT_MATRIX
        .iter()
        .find(|row| row.operation == operation)
        .unwrap_or_else(|| panic!("missing project matrix row for {operation:?}"))
}

#[expect(
    clippy::too_many_arguments,
    reason = "project compiler matrix rows are clearer when each dimension is asserted explicitly"
)]
fn assert_row_shape(
    row: MatrixRow,
    event_variant: EventVariant,
    sync_mode: SyncMode,
    insert_payload: InsertPayload,
    remove_payload: RemovePayload,
    path_relations: &[PathRelation],
    batch_shape: BatchShape,
    sequence_shape: SequenceShape,
    expected: ExpectedOutcome,
) {
    assert_eq!(row.event_variant, event_variant);
    assert_eq!(row.sync_mode, sync_mode);
    assert_eq!(row.insert_payload, insert_payload);
    assert_eq!(row.remove_payload, remove_payload);
    assert_eq!(row.path_relations, path_relations);
    assert_eq!(row.batch_shape, batch_shape);
    assert_eq!(row.sequence_shape, sequence_shape);
    assert_eq!(row.expected, expected);
}
fn run_matrix_row(row: MatrixRow) {
    match row.operation {
        MatrixOperation::InitialSync => assert_initial_sync(row),
        MatrixOperation::FollowUpNonSyncUpdate => assert_follow_up_non_sync_update(row),
        MatrixOperation::CreateDependency => assert_create_dependency(row),
        MatrixOperation::EditEntry => assert_edit_entry(row),
        MatrixOperation::EditDependency => assert_edit_dependency(row),
        MatrixOperation::CreateUnrelated => assert_create_unrelated(row),
        MatrixOperation::RemoveDependency => assert_remove_dependency(row),
        MatrixOperation::ReadErrorDependency => assert_read_error_dependency(row),
        MatrixOperation::EmptyDependency => assert_empty_dependency(row),
        MatrixOperation::EmptyUnrelated => assert_empty_unrelated(row),
        MatrixOperation::RenameUpdatedReferences => assert_rename_updated_references(row),
        MatrixOperation::RenameStaleReferences => assert_rename_stale_references(row),
        MatrixOperation::DeleteThenRecreate => assert_delete_then_recreate(row),
        MatrixOperation::FailedReadThenRecovery => assert_failed_read_then_recovery(row),
        MatrixOperation::RenameBatch => assert_rename_batch(row),
        MatrixOperation::MultiFileUnrelatedBatch => assert_multi_file_unrelated_batch(row),
        MatrixOperation::UpstreamInvalidation => assert_upstream_invalidation(row),
        MatrixOperation::UnrelatedChurn => assert_unrelated_churn(row),
        MatrixOperation::EmptyChangeset => assert_empty_changeset(row),
        MatrixOperation::DependencyMembershipRemoval => {
            assert_dependency_membership_removal(row);
        }
        MatrixOperation::DependencyMembershipReaddition => {
            assert_dependency_membership_readdition(row);
        }
    }
}

#[test]
fn project_compiler_fs_event_matrix_is_explicit() {
    for row in PROJECT_COMPILER_FS_EVENT_MATRIX {
        assert!(!row.path_relations.is_empty());
    }

    for operation in [
        MatrixOperation::InitialSync,
        MatrixOperation::FollowUpNonSyncUpdate,
        MatrixOperation::CreateDependency,
        MatrixOperation::EditEntry,
        MatrixOperation::EditDependency,
        MatrixOperation::CreateUnrelated,
        MatrixOperation::RemoveDependency,
        MatrixOperation::ReadErrorDependency,
        MatrixOperation::EmptyDependency,
        MatrixOperation::EmptyUnrelated,
        MatrixOperation::RenameUpdatedReferences,
        MatrixOperation::RenameStaleReferences,
        MatrixOperation::DeleteThenRecreate,
        MatrixOperation::FailedReadThenRecovery,
        MatrixOperation::RenameBatch,
        MatrixOperation::MultiFileUnrelatedBatch,
        MatrixOperation::UpstreamInvalidation,
        MatrixOperation::UnrelatedChurn,
        MatrixOperation::EmptyChangeset,
        MatrixOperation::DependencyMembershipRemoval,
        MatrixOperation::DependencyMembershipReaddition,
    ] {
        assert_matrix_contains(operation, |row| row.operation == operation);
    }
    for variant in [EventVariant::Update, EventVariant::UpstreamUpdate] {
        assert_matrix_contains(variant, |row| row.event_variant == variant);
    }
    for sync_mode in [SyncMode::Sync, SyncMode::NonSync, SyncMode::NotApplicable] {
        assert_matrix_contains(sync_mode, |row| row.sync_mode == sync_mode);
    }
    for payload in [
        InsertPayload::NonEmptyContent,
        InsertPayload::EmptyContent,
        InsertPayload::ReadErrorSnapshot,
        InsertPayload::NoInserts,
    ] {
        assert_matrix_contains(payload, |row| row.insert_payload == payload);
    }
    for payload in [
        RemovePayload::NoRemoves,
        RemovePayload::OneRemovedPath,
        RemovePayload::MultipleRemovedPaths,
    ] {
        assert_matrix_contains(payload, |row| row.remove_payload == payload);
    }
    for relation in [
        PathRelation::EntryFile,
        PathRelation::ImportedDependency,
        PathRelation::PreviouslyDependedPath,
        PathRelation::NewlyCreatedDependency,
        PathRelation::NewlyReferencedDependency,
        PathRelation::RetainedInactiveDependency,
        PathRelation::UnrelatedFile,
    ] {
        assert_matrix_contains(relation, |row| row.path_relations.contains(&relation));
    }
    for batch in [
        BatchShape::InsertOnly,
        BatchShape::RemoveOnly,
        BatchShape::RemovePlusInsert,
        BatchShape::MultiFileBatch,
        BatchShape::EmptyChangeset,
        BatchShape::RemoveOnlyThenInsertOnly,
    ] {
        assert_matrix_contains(batch, |row| row.batch_shape == batch);
    }
    for sequence in [
        SequenceShape::InitialSync,
        SequenceShape::OneStepEdit,
        SequenceShape::CreateAfterMissingImport,
        SequenceShape::OneStepRemove,
        SequenceShape::RenameOldPlusNew,
        SequenceShape::FailedRead,
        SequenceShape::FailedReadThenRecovery,
        SequenceShape::TransientEmptyWrite,
        SequenceShape::DeleteThenRecreate,
        SequenceShape::DelayedMemoryThenFilesystem,
        SequenceShape::EmptyChangeset,
    ] {
        assert_matrix_contains(sequence, |row| row.sequence_shape == sequence);
    }

    for omitted in OMITTED_PROJECT_COMPILER_FS_EVENT_COMBINATIONS {
        assert!(matches!(
            omitted.reason,
            OmissionReason::Unreachable | OmissionReason::Redundant | OmissionReason::Deferred
        ));
        assert!(matches!(
            omitted.combination,
            OmittedEventCombination::SyncFlagOnUpstreamUpdate
                | OmittedEventCombination::EntryFileReadErrorAfterDirectClientInput
                | OmittedEventCombination::BackendSpecificNotifyRenameQuirk
        ));
    }
}

#[test]
fn project_compiler_fs_event_matrix_rows_execute_expected_outcomes() {
    for row in PROJECT_COMPILER_FS_EVENT_MATRIX {
        run_matrix_row(*row);
    }
}

#[test]
fn project_compiler_compile_cache_matrix_covers_vfs_operation_rows() {
    for id in [
        OperationId::O01,
        OperationId::O02,
        OperationId::O03,
        OperationId::O04,
        OperationId::O05,
        OperationId::O06,
        OperationId::O07,
        OperationId::O08,
        OperationId::O09,
        OperationId::O10,
        OperationId::O11,
        OperationId::O12,
        OperationId::O13,
        OperationId::O14,
        OperationId::O15,
        OperationId::O16,
        OperationId::O17,
        OperationId::O18,
        OperationId::O19,
        OperationId::O20,
    ] {
        assert_compile_cache_matrix_contains(id);
    }

    for coverage in VFS_OPERATION_COMPILE_CACHE_MATRIX {
        assert!(
            !coverage.matrix_operations.is_empty(),
            "{} must have an executable project compiler representative",
            coverage.id.label()
        );
        assert!(
            !coverage.note.is_empty(),
            "{} must document its project compile-cache equivalence",
            coverage.id.label()
        );

        for operation in coverage.matrix_operations {
            run_matrix_row(project_matrix_row(*operation));
        }
    }
}

fn assert_initial_sync(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::Sync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::EntryFile, PathRelation::ImportedDependency],
        BatchShape::MultiFileBatch,
        SequenceShape::InitialSync,
        ExpectedOutcome::IgnoredFirstSync,
    );

    let files = default_files();
    let mut harness = ProjectCompilerHarness::ignoring_first_sync(&files);
    let initial = harness.compile_primary();
    assert_eq!(initial.error_cnt(), 0);
    harness.latest_sync_dependencies();

    let sync = MockChange::new(harness.workspace.sync_changeset());
    row.apply_update(&mut harness, &sync);
    assert!(
        !harness.compiler.primary.reason.any(),
        "initial sync should not create a compile reason when ignored"
    );
}

fn assert_follow_up_non_sync_update(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::ImportedDependency],
        BatchShape::InsertOnly,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::FsReasonRefreshesDependency,
    );

    let files = default_files();
    let mut harness = ProjectCompilerHarness::ignoring_first_sync(&files);
    let initial = harness.compile_primary();
    assert_eq!(initial.error_cnt(), 0);
    harness.latest_sync_dependencies();

    let sync = MockChange::new(harness.workspace.sync_changeset());
    harness.apply_update(&sync, true);
    assert!(!harness.compiler.primary.reason.any());

    let follow_up = harness
        .workspace
        .update_source(DEP, "#let value = [after sync]");
    row.apply_update(&mut harness, &follow_up);
    assert_fs_reason(&harness.compiler);

    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, DEP),
        "#let value = [after sync]"
    );
    let deps = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps, DEP);
}

fn assert_create_dependency(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::NewlyCreatedDependency],
        BatchShape::InsertOnly,
        SequenceShape::CreateAfterMissingImport,
        ExpectedOutcome::RecoversNewDependency,
    );

    let files = vec![
        (
            MAIN,
            "#import \"dep.typ\": value\n#import \"new.typ\": newer\n#value\n#newer",
        ),
        (DEP, "#let value = [before]"),
    ];
    let mut harness = ProjectCompilerHarness::new(&files);
    let initial = harness.compile_primary();
    assert!(initial.error_cnt() > 0);
    harness.latest_sync_dependencies();

    let created_dependency = harness
        .workspace
        .create_source("new.typ", "#let newer = [new dependency]");
    row.apply_update(&mut harness, &created_dependency);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, "new.typ"),
        "#let newer = [new dependency]"
    );
    let deps = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps, "new.typ");
}

fn assert_edit_entry(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::EntryFile],
        BatchShape::InsertOnly,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::RefreshesEntrySource,
    );

    let mut harness = clean_default_harness();
    let entry_edit = harness.workspace.update_source(
        MAIN,
        "#import \"dep.typ\": value\n#let local = [entry changed]\n#value\n#local",
    );
    row.apply_update(&mut harness, &entry_edit);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, MAIN),
        "#import \"dep.typ\": value\n#let local = [entry changed]\n#value\n#local"
    );
}

fn assert_edit_dependency(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::ImportedDependency],
        BatchShape::InsertOnly,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::RefreshesDependencySource,
    );

    let mut harness = clean_default_harness();
    let dependency_edit = harness
        .workspace
        .update_source(DEP, "#let value = [dependency changed]");
    row.apply_update(&mut harness, &dependency_edit);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, DEP),
        "#let value = [dependency changed]"
    );
}

fn assert_create_unrelated(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::UnrelatedFile],
        BatchShape::InsertOnly,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::KeepsUnrelatedCreateHarmless,
    );

    let (mut harness, deps_before) = clean_default_harness_with_deps();
    let unrelated_create = harness
        .workspace
        .create_source("scratch.typ", "#let scratch = [unused]");
    row.apply_update(&mut harness, &unrelated_create);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps_after = harness.dependency_paths_after_harmless_compile(&deps_before);
    assert_eq!(deps_after, deps_before);
    assert_deps_do_not_contain(&harness.workspace, &deps_after, "scratch.typ");
}

fn assert_remove_dependency(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NoInserts,
        RemovePayload::OneRemovedPath,
        &[PathRelation::PreviouslyDependedPath],
        BatchShape::RemoveOnly,
        SequenceShape::OneStepRemove,
        ExpectedOutcome::ReportsRetiredDependencyUnavailable,
    );

    let mut harness = clean_default_harness();
    let removed = harness.workspace.remove(DEP).unwrap();
    row.apply_update(&mut harness, &removed);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert!(artifact.error_cnt() > 0);
    assert!(source_is_unavailable(&artifact, &harness.workspace, DEP));
}

fn assert_read_error_dependency(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::ReadErrorSnapshot,
        RemovePayload::NoRemoves,
        &[PathRelation::ImportedDependency],
        BatchShape::InsertOnly,
        SequenceShape::FailedRead,
        ExpectedOutcome::SurfacesReadErrorDiagnostics,
    );

    let mut harness = clean_default_harness();
    let read_error = read_error_change(&harness.workspace, DEP);
    row.apply_update(&mut harness, &read_error);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert!(artifact.error_cnt() > 0);
    assert!(source_is_unavailable(&artifact, &harness.workspace, DEP));
}

fn assert_empty_dependency(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::EmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::ImportedDependency],
        BatchShape::InsertOnly,
        SequenceShape::TransientEmptyWrite,
        ExpectedOutcome::UsesEmptyDependencySnapshot,
    );

    let mut harness = clean_default_harness();
    let empty_dependency = harness.workspace.update_source(DEP, "");
    row.apply_update(&mut harness, &empty_dependency);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert!(artifact.error_cnt() > 0);
    assert_eq!(source_text(&artifact, &harness.workspace, DEP), "");
}

fn assert_empty_unrelated(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::EmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::UnrelatedFile],
        BatchShape::InsertOnly,
        SequenceShape::TransientEmptyWrite,
        ExpectedOutcome::KeepsEmptyUnrelatedHarmless,
    );

    let (mut harness, deps_before) = clean_default_harness_with_deps();
    let empty_unrelated = harness.workspace.update_source(UNRELATED, "");
    row.apply_update(&mut harness, &empty_unrelated);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps_after = harness.dependency_paths_after_harmless_compile(&deps_before);
    assert_eq!(deps_after, deps_before);
    assert_deps_do_not_contain(&harness.workspace, &deps_after, UNRELATED);
}

fn assert_rename_updated_references(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::OneRemovedPath,
        &[
            PathRelation::PreviouslyDependedPath,
            PathRelation::NewlyReferencedDependency,
        ],
        BatchShape::RemovePlusInsert,
        SequenceShape::RenameOldPlusNew,
        ExpectedOutcome::FollowsRenamedPath,
    );

    let mut harness = clean_default_harness();
    let rename = harness.workspace.rename(DEP, RENAMED_DEP).unwrap();
    row.apply_update(&mut harness, &rename);
    let entry_update = harness
        .workspace
        .update_source(MAIN, "#import \"renamed.typ\": value\n#value");
    harness.apply_update(&entry_update, false);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert!(source_is_unavailable(&artifact, &harness.workspace, DEP));
    assert_eq!(
        source_text(&artifact, &harness.workspace, RENAMED_DEP),
        "#let value = [before]"
    );
    let deps = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps, RENAMED_DEP);
    assert_deps_do_not_contain(&harness.workspace, &deps, DEP);
}

fn assert_rename_stale_references(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::OneRemovedPath,
        &[PathRelation::PreviouslyDependedPath],
        BatchShape::RemovePlusInsert,
        SequenceShape::RenameOldPlusNew,
        ExpectedOutcome::ReportsOldImportUnavailable,
    );

    let mut harness = clean_default_harness();
    let rename = harness.workspace.rename(DEP, RENAMED_DEP).unwrap();
    row.apply_update(&mut harness, &rename);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert!(artifact.error_cnt() > 0);
    assert!(source_is_unavailable(&artifact, &harness.workspace, DEP));
    assert_eq!(
        source_text(&artifact, &harness.workspace, RENAMED_DEP),
        "#let value = [before]"
    );
}

fn assert_delete_then_recreate(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::OneRemovedPath,
        &[PathRelation::PreviouslyDependedPath],
        BatchShape::RemoveOnlyThenInsertOnly,
        SequenceShape::DeleteThenRecreate,
        ExpectedOutcome::ReportsThenRecoversRecreatedSource,
    );

    let mut harness = clean_default_harness();
    let removed = harness.workspace.remove(DEP).unwrap();
    row.apply_update(&mut harness, &removed);
    let artifact = harness.compile_pending();
    assert!(artifact.error_cnt() > 0);
    assert!(source_is_unavailable(&artifact, &harness.workspace, DEP));
    harness.latest_sync_dependencies();

    let recreated = harness
        .workspace
        .create_source(DEP, "#let value = [recreated]");
    row.apply_update(&mut harness, &recreated);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, DEP),
        "#let value = [recreated]"
    );
    let deps = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps, DEP);
}

fn assert_failed_read_then_recovery(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::ImportedDependency],
        BatchShape::InsertOnly,
        SequenceShape::FailedReadThenRecovery,
        ExpectedOutcome::ClearsDiagnosticsAfterRecovery,
    );

    let mut harness = clean_default_harness();
    let read_error = read_error_change(&harness.workspace, DEP);
    row.apply_update(&mut harness, &read_error);
    let artifact = harness.compile_pending();
    assert!(artifact.error_cnt() > 0);
    assert!(source_is_unavailable(&artifact, &harness.workspace, DEP));
    harness.latest_sync_dependencies();

    let recovered = harness
        .workspace
        .update_source(DEP, "#let value = [recovered]");
    row.apply_update(&mut harness, &recovered);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, DEP),
        "#let value = [recovered]"
    );
    let deps = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps, DEP);
}

fn assert_rename_batch(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::OneRemovedPath,
        &[
            PathRelation::PreviouslyDependedPath,
            PathRelation::NewlyReferencedDependency,
        ],
        BatchShape::RemovePlusInsert,
        SequenceShape::RenameOldPlusNew,
        ExpectedOutcome::RenameBatchFollowsRenamedPath,
    );

    let mut harness = clean_default_harness();
    let rename = harness.workspace.rename(DEP, RENAMED_DEP).unwrap();
    let entry_update = harness
        .workspace
        .update_source(MAIN, "#import \"renamed.typ\": value\n#value");
    let batch = combine_changes(&[rename, entry_update]);
    row.apply_update(&mut harness, &batch);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps, RENAMED_DEP);
    assert_deps_do_not_contain(&harness.workspace, &deps, DEP);
}

fn assert_multi_file_unrelated_batch(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::MultipleRemovedPaths,
        &[PathRelation::UnrelatedFile],
        BatchShape::MultiFileBatch,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::MultiFileUnrelatedBatchHarmless,
    );

    let files = vec![
        (MAIN, "#import \"dep.typ\": value\n#value"),
        (DEP, "#let value = [before]"),
        ("old-a.typ", "#let old_a = [unused]"),
        ("old-b.typ", "#let old_b = [unused]"),
    ];
    let mut harness = ProjectCompilerHarness::new(&files);
    let initial = harness.compile_primary();
    assert_eq!(initial.error_cnt(), 0);
    let deps_before = harness.latest_sync_dependencies();

    let remove_a = harness.workspace.remove("old-a.typ").unwrap();
    let remove_b = harness.workspace.remove("old-b.typ").unwrap();
    let create_a = harness
        .workspace
        .create_source("new-a.typ", "#let new_a = [unused]");
    let create_b = harness
        .workspace
        .create_source("new-b.typ", "#let new_b = [unused]");
    let batch = combine_changes(&[remove_a, remove_b, create_a, create_b]);
    row.apply_update(&mut harness, &batch);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps_after = harness.dependency_paths_after_harmless_compile(&deps_before);
    assert_eq!(deps_after, deps_before);
    assert_deps_do_not_contain(&harness.workspace, &deps_after, "new-a.typ");
    assert_deps_do_not_contain(&harness.workspace, &deps_after, "new-b.typ");
}

fn assert_upstream_invalidation(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::UpstreamUpdate,
        SyncMode::NotApplicable,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::EntryFile],
        BatchShape::InsertOnly,
        SequenceShape::DelayedMemoryThenFilesystem,
        ExpectedOutcome::AppliesDelayedMemoryBeforeFilesystem,
    );

    let files = vec![(MAIN, "#let value = [disk]\n#value")];
    let mut harness = ProjectCompilerHarness::new(&files);
    let initial = harness.compile_primary();
    assert_eq!(initial.error_cnt(), 0);
    harness.latest_sync_dependencies();

    let memory_insert = insert_source_change(
        &harness.workspace,
        MAIN,
        "#let value = [memory shadow]\n#value",
    );
    harness
        .compiler
        .process(Interrupt::Memory(memory_insert.memory_event()));
    assert_mem_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(
        source_text(&artifact, &harness.workspace, MAIN),
        "#let value = [memory shadow]\n#value"
    );
    harness.latest_sync_dependencies();

    let memory_remove = remove_change(&harness.workspace, MAIN);
    harness
        .compiler
        .process(Interrupt::Memory(memory_remove.memory_event()));
    let upstream_event = harness.take_upstream_update();
    assert!(
        upstream_event
            .invalidates
            .contains(&harness.workspace.immut_path(MAIN))
    );
    assert!(
        !harness.compiler.primary.reason.any(),
        "delayed memory removal should wait for the upstream filesystem event"
    );

    let filesystem_update = harness
        .workspace
        .update_source(MAIN, "#let value = [filesystem]\n#value");
    harness.apply_upstream_update(filesystem_update.into_changeset(), Some(upstream_event));
    assert_fs_reason(&harness.compiler);
    assert!(
        !harness.compiler.primary.reason.by_mem_events,
        "known upstream update should not add a separate memory reason"
    );

    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, MAIN),
        "#let value = [filesystem]\n#value"
    );
}

fn assert_unrelated_churn(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[PathRelation::UnrelatedFile],
        BatchShape::InsertOnly,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::KeepsUnrelatedChurnHarmless,
    );

    let (mut harness, deps_before) = clean_default_harness_with_deps();
    let unrelated = harness
        .workspace
        .update_source(UNRELATED, "#let note = [changed but unused]");
    row.apply_update(&mut harness, &unrelated);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps_after = harness.dependency_paths_after_harmless_compile(&deps_before);
    assert_eq!(deps_after, deps_before);
    assert_deps_do_not_contain(&harness.workspace, &deps_after, UNRELATED);
}

fn assert_empty_changeset(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NoInserts,
        RemovePayload::NoRemoves,
        &[PathRelation::UnrelatedFile],
        BatchShape::EmptyChangeset,
        SequenceShape::EmptyChangeset,
        ExpectedOutcome::ExplicitNoContentOutcome,
    );

    let (mut harness, deps_before) = clean_default_harness_with_deps();
    let empty = empty_change();
    row.apply_update(&mut harness, &empty);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps_after = harness.dependency_paths_after_harmless_compile(&deps_before);
    assert_eq!(deps_after, deps_before);
}

fn assert_dependency_membership_removal(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[
            PathRelation::EntryFile,
            PathRelation::RetainedInactiveDependency,
        ],
        BatchShape::InsertOnly,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::DropsInactiveDependency,
    );

    let (mut harness, deps_before) = clean_default_harness_with_deps();
    assert_deps_contain(&harness.workspace, &deps_before, DEP);

    let entry_without_dependency = harness
        .workspace
        .update_source(MAIN, "#let value = [inline]\n#value");
    row.apply_update(&mut harness, &entry_without_dependency);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, MAIN),
        "#let value = [inline]\n#value"
    );
    let deps_after = harness.dependency_paths_after_compile();
    assert_deps_do_not_contain(&harness.workspace, &deps_after, DEP);
}

fn assert_dependency_membership_readdition(row: MatrixRow) {
    assert_row_shape(
        row,
        EventVariant::Update,
        SyncMode::NonSync,
        InsertPayload::NonEmptyContent,
        RemovePayload::NoRemoves,
        &[
            PathRelation::EntryFile,
            PathRelation::RetainedInactiveDependency,
            PathRelation::ImportedDependency,
        ],
        BatchShape::MultiFileBatch,
        SequenceShape::OneStepEdit,
        ExpectedOutcome::ReaddsChangedInactiveDependency,
    );

    let (mut harness, deps_before) = clean_default_harness_with_deps();
    assert_deps_contain(&harness.workspace, &deps_before, DEP);

    let entry_without_dependency = harness
        .workspace
        .update_source(MAIN, "#let value = [inline]\n#value");
    harness.apply_update(&entry_without_dependency, false);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    let deps_without_dependency = harness.dependency_paths_after_compile();
    assert_deps_do_not_contain(&harness.workspace, &deps_without_dependency, DEP);

    let changed_while_inactive = harness
        .workspace
        .update_source(DEP, "#let value = [changed while inactive]");
    let entry_readd = harness
        .workspace
        .update_source(MAIN, "#import \"dep.typ\": value\n#value");
    row.apply_update(&mut harness, &entry_readd);
    harness.apply_update(&changed_while_inactive, true);
    assert_fs_reason(&harness.compiler);
    let artifact = harness.compile_pending();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        source_text(&artifact, &harness.workspace, DEP),
        "#let value = [changed while inactive]"
    );
    let deps_after = harness.dependency_paths_after_compile();
    assert_deps_contain(&harness.workspace, &deps_after, DEP);
}
