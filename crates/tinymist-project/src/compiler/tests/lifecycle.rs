//! Demand, revision and project-lifetime regressions.

use super::*;

#[test]
fn clean_demand_cycle_preserves_committed_ticket_for_save_replay() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    harness
        .compiler
        .process(Interrupt::Compile(ProjectInsId::PRIMARY));
    let handler = harness.compiler.handler.clone();
    let (_, work) = harness
        .compiler
        .primary
        .may_compile_latest(&handler)
        .unwrap();
    let artifact = work().artifact.unwrap();
    harness
        .compiler
        .process(Interrupt::Compiled(artifact.clone()));
    harness.compiler.primary.set_demand(false);
    harness.compiler.primary.set_demand(true);
    let path = artifact
        .world()
        .file_path(artifact.world().main())
        .unwrap()
        .to_err()
        .unwrap();
    harness.compiler.process(Interrupt::Save(path.into()));
    assert!(harness.compiler.primary.accepts_artifact(&artifact));
    assert!(harness.compiler.primary.reason.by_fs_events);
    harness.compiler.primary.invalidate_compiles();
    assert!(!harness.compiler.primary.accepts_artifact(&artifact));
}

#[test]
fn dark_only_preview_keeps_one_active_cache_maintenance_owner() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    let entry = harness.compiler.primary.verse.entry_state();
    let dark = harness.compiler.restart_dedicate("dark", entry).unwrap();
    assert_eq!(harness.compiler.cache_owner(), Some(&ProjectInsId::PRIMARY));
    harness.compiler.primary.set_demand(false);
    assert_eq!(harness.compiler.cache_owner(), Some(&dark));
    harness.compiler.dedicates[0].set_demand(false);
    assert_eq!(harness.compiler.cache_owner(), None);
    harness.compiler.dedicates[0].set_demand(true);
    harness.compiler.primary.set_demand(true);
    assert_eq!(harness.compiler.cache_owner(), Some(&ProjectInsId::PRIMARY));
}

#[test]
fn dual_theme_preview_sweeps_once_after_final_demanded_project_commits() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    let entry = harness.compiler.primary.verse.entry_state();
    let dark = harness.compiler.restart_dedicate("dark", entry).unwrap();
    harness
        .compiler
        .process(Interrupt::Compile(ProjectInsId::PRIMARY));
    let handler = harness.compiler.handler.clone();

    // Both primary and dark have pending work at revision 2.
    assert!(
        !harness
            .compiler
            .maintains_shared_cache(&ProjectInsId::PRIMARY)
    );
    assert!(!harness.compiler.maintains_shared_cache(&dark));

    let (_, primary_work) = harness
        .compiler
        .primary
        .may_compile_latest(&handler)
        .unwrap();
    let primary_art = primary_work().artifact.unwrap();
    // Primary finishes while dark is still uncommitted, so it must not sweep early.
    assert!(
        !harness
            .compiler
            .maintains_shared_cache(&ProjectInsId::PRIMARY)
    );
    harness.compiler.process(Interrupt::Compiled(primary_art));

    let (_, dark_work) = harness.compiler.dedicates[0]
        .may_compile_latest(&handler)
        .unwrap();
    let dark_art = dark_work().artifact.unwrap();
    // Dark finishes after primary has already committed, so dark runs the sweep.
    assert!(harness.compiler.maintains_shared_cache(&dark));
    harness.compiler.process(Interrupt::Compiled(dark_art));
}

#[test]
fn superseded_queued_compile_skips_execution_and_latest_compiles() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    harness
        .compiler
        .process(Interrupt::Compile(ProjectInsId::PRIMARY));
    let handler = harness.compiler.handler.clone();
    let (old_ticket, old_work) = harness
        .compiler
        .primary
        .may_compile_latest(&handler)
        .unwrap();
    let change = harness.workspace.update_source(MAIN, "#let value = 2");
    harness.apply_update(&change, false);
    let old = old_work();
    assert!(old_ticket.same_task(&old.ticket));
    assert!(!old.executed);
    assert!(
        old.artifact.is_none(),
        "obsolete queued work must not read or compile its world"
    );
    let (_, latest_work) = harness
        .compiler
        .primary
        .may_compile_latest(&handler)
        .unwrap();
    let latest = latest_work();
    assert!(latest.is_publishable());
    assert!(latest.executed);
    let artifact = latest.artifact.unwrap();
    assert_eq!(artifact.error_cnt(), 0);
    assert_eq!(
        artifact
            .world()
            .source(artifact.world().main())
            .unwrap()
            .text(),
        "#let value = 2",
    );
}

#[test]
fn completed_result_becomes_stale_before_actor_publication() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    harness
        .compiler
        .process(Interrupt::Compile(ProjectInsId::PRIMARY));
    let handler = harness.compiler.handler.clone();
    let (_, work) = harness
        .compiler
        .primary
        .may_compile_latest(&handler)
        .unwrap();
    let outcome = work();
    assert!(outcome.is_publishable());
    let change = harness.workspace.update_source(MAIN, "#let value = 2");
    harness.apply_update(&change, false);
    assert!(!outcome.is_publishable());
    let artifact = outcome.artifact.unwrap();
    assert!(!harness.compiler.primary.accepts_artifact(&artifact));
    harness.compiler.process(Interrupt::Compiled(artifact));
    assert_eq!(harness.compiler.primary.committed_revision, 0);
}

#[test]
fn demand_pause_keeps_latest_changes_and_clean_resume_reuses_result() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    harness.compile_primary();
    let handler = harness.compiler.handler.clone();
    harness
        .compiler
        .process(Interrupt::SetDemand(ProjectInsId::PRIMARY, false));
    harness
        .compiler
        .process(Interrupt::SetDemand(ProjectInsId::PRIMARY, true));
    assert!(
        harness
            .compiler
            .primary
            .may_compile_latest(&handler)
            .is_none()
    );

    harness
        .compiler
        .process(Interrupt::SetDemand(ProjectInsId::PRIMARY, false));
    for value in 2..5 {
        let change = harness
            .workspace
            .update_source(MAIN, format!("#let value = {value}"));
        harness.apply_update(&change, false);
    }
    assert!(
        harness
            .compiler
            .primary
            .may_compile_latest(&handler)
            .is_none()
    );
    harness
        .compiler
        .process(Interrupt::SetDemand(ProjectInsId::PRIMARY, true));
    let (_, work) = harness
        .compiler
        .primary
        .may_compile_latest(&handler)
        .unwrap();
    let outcome = work();
    let artifact = outcome.artifact.unwrap();
    assert_eq!(
        artifact
            .world()
            .source(artifact.world().main())
            .unwrap()
            .text(),
        "#let value = 4"
    );
}

#[test]
fn removing_project_invalidates_queued_work_without_reusing_its_lifetime() {
    let mut harness = ProjectCompilerHarness::new(&[(MAIN, "#let value = 1")]);
    let entry = harness.compiler.primary.verse.entry_state();
    let id = harness
        .compiler
        .restart_dedicate("preview", entry.clone())
        .unwrap();
    let handler = harness.compiler.handler.clone();
    let (old_ticket, old_work) = harness.compiler.dedicates[0]
        .may_compile_latest(&handler)
        .unwrap();
    harness.compiler.restart_dedicate("preview", entry).unwrap();
    let (new_ticket, _) = harness.compiler.dedicates[0]
        .may_compile_latest(&handler)
        .unwrap();
    assert_eq!(old_ticket.id, id);
    assert!(!old_ticket.same_task(&new_ticket));
    assert!(old_work().artifact.is_none());
}
