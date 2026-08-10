from __future__ import annotations

import os
from collections import Counter
from pathlib import Path
from typing import Annotated

import typer
from rich import box
from rich.console import Console
from rich.progress import BarColumn, MofNCompleteColumn, Progress, SpinnerColumn, TextColumn
from rich.table import Table
from rich.text import Text

from step_by_sample import __version__
from step_by_sample.config import load_config, write_starter_config
from step_by_sample.core import (
    generate_jobs,
    inspect_status,
    read_run_list,
    reset_failed,
    run_jobs,
    status_counts,
    submit_jobs,
    validate_inputs,
)
from step_by_sample.models import SampleState, SelectionMode, StepBySampleError

app = typer.Typer(
    name="step-by-sample",
    help="[bold cyan]Run one command independently for every sample.[/bold cyan]",
    epilog="Use [bold]step-by-sample COMMAND --help[/bold] for command-specific examples.",
    no_args_is_help=True,
    rich_markup_mode="rich",
    context_settings={"help_option_names": ["-h", "--help"]},
)


def _console(*, stderr: bool = False) -> Console:
    return Console(stderr=stderr, no_color="NO_COLOR" in os.environ)


def _abort(error: Exception) -> None:
    _console(stderr=True).print("[bold red]Error:[/bold red]", Text(str(error)))
    raise typer.Exit(1)


def _version_callback(value: bool) -> None:
    if value:
        typer.echo(f"step-by-sample {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: Annotated[
        bool | None,
        typer.Option(
            "--version", callback=_version_callback, is_eager=True, help="Show the version."
        ),
    ] = None,
) -> None:
    """A small, explicit workflow runner for local machines and Slurm clusters."""


@app.command("init")
def init_command(
    config: Annotated[
        Path,
        typer.Argument(help="Configuration file to create."),
    ] = Path("step-by-sample.toml"),
    force: Annotated[
        bool,
        typer.Option("--force", help="Replace an existing configuration file."),
    ] = False,
) -> None:
    """Create a documented starter configuration."""
    try:
        created = write_starter_config(config, force=force)
    except (OSError, StepBySampleError) as exc:
        _abort(exc)
    console = _console()
    console.print("[bold green]Created[/bold green]", Text(str(created)))
    console.print("Edit the paths and command, then run:")
    console.print("  [bold cyan]step-by-sample generate[/bold cyan]", Text(str(created)))


@app.command()
def generate(
    config: Annotated[
        Path,
        typer.Argument(help="TOML step configuration."),
    ] = Path("step-by-sample.toml"),
    mode: Annotated[
        SelectionMode | None,
        typer.Option("--mode", help="Override the configured sample selection mode."),
    ] = None,
    force: Annotated[
        bool,
        typer.Option("--force", help="Generate jobs for every sample regardless of status."),
    ] = False,
    strict: Annotated[
        bool | None,
        typer.Option("--strict/--no-strict", help="Override missing-input handling."),
    ] = None,
    verbose: Annotated[
        bool,
        typer.Option("-v", "--verbose", help="List every selected and skipped sample."),
    ] = False,
) -> None:
    """Generate per-sample jobs and an absolute-path run list."""
    try:
        settings = load_config(config).with_runtime_options(mode=mode, strict=strict)
        result = generate_jobs(settings, force=force)
    except (OSError, StepBySampleError) as exc:
        _abort(exc)

    console = _console()
    console.print(
        "[bold cyan]Generating[/bold cyan]",
        f"mode={settings.mode.value}",
        "from",
        Text(str(settings.input_dir)),
    )
    if verbose:
        for sample in result.created:
            console.print("  [green]ADD[/green] ", Text(sample))
        for sample in result.skipped:
            console.print("  [dim]SKIP[/dim]", Text(sample))
    for sample in result.missing:
        console.print("  [yellow]MISSING[/yellow]", Text(sample))

    table = Table(box=box.ROUNDED, show_header=False, title="Generation summary")
    table.add_column("Metric", style="bold")
    table.add_column("Value", justify="right")
    table.add_row("Samples", str(result.total))
    table.add_row("Jobs created", f"[green]{len(result.created)}[/green]")
    table.add_row("Missing input", f"[yellow]{len(result.missing)}[/yellow]")
    table.add_row("Status skipped", str(len(result.skipped)))
    console.print(table)
    console.print("Run list:", Text(str(result.run_list)))
    console.print("Job directory:", Text(str(result.job_dir)))
    if not result.created and not result.missing:
        console.print("[bold green]Nothing to do — selected samples are complete.[/bold green]")
    if settings.strict and result.missing:
        _abort(
            StepBySampleError(
                f"strict mode: {len(result.missing)} sample(s) are missing expected input"
            )
        )


@app.command("run")
def run_command(
    run_list: Annotated[Path, typer.Argument(help="Run list produced by generate.")],
    jobs: Annotated[
        int,
        typer.Option("-j", "--jobs", min=1, help="Maximum concurrent sample jobs."),
    ] = 1,
    verbose: Annotated[
        bool,
        typer.Option("-v", "--verbose", help="Show output from successful jobs too."),
    ] = False,
) -> None:
    """Execute a run list locally with bounded parallelism."""
    console = _console()
    try:
        scripts = read_run_list(run_list)
        console.print(
            f"[bold cyan]Running {len(scripts)} sample job(s)[/bold cyan] with up to {jobs} workers"
        )
        progress = Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            MofNCompleteColumn(),
            console=console,
            disable=not console.is_terminal,
        )
        with progress:
            task = progress.add_task("Samples", total=len(scripts))
            results = run_jobs(
                run_list,
                jobs=jobs,
                on_complete=lambda _result: progress.advance(task),
            )
    except (OSError, StepBySampleError) as exc:
        _abort(exc)

    failures = [result for result in results if not result.succeeded]
    if verbose:
        for result in results:
            output = (result.stdout + result.stderr).rstrip()
            if output:
                console.rule(Text(result.script.name))
                console.print(Text(output))
    elif failures:
        for result in failures:
            output = (result.stdout + result.stderr).rstrip()
            console.print("[bold red]FAILED[/bold red]", Text(result.script.name))
            if output:
                console.print(Text(output))

    table = Table(box=box.SIMPLE_HEAVY, show_header=False)
    table.add_column("Result", style="bold")
    table.add_column("Count", justify="right")
    table.add_row("Completed", f"[green]{len(results) - len(failures)}[/green]")
    table.add_row("Failed", f"[red]{len(failures)}[/red]")
    console.print(table)
    if failures:
        raise typer.Exit(1)


@app.command()
def submit(
    run_list: Annotated[Path, typer.Argument(help="Run list produced by generate.")],
    account: Annotated[str | None, typer.Option(help="Slurm account.")] = None,
    partition: Annotated[str | None, typer.Option(help="Slurm partition.")] = None,
    time: Annotated[str, typer.Option(help="Wall time.")] = "04:00:00",
    memory: Annotated[str, typer.Option("--mem", help="Memory per array task.")] = "8G",
    cpus: Annotated[int, typer.Option(min=1, help="CPUs per array task.")] = 4,
    array_max: Annotated[
        int,
        typer.Option("--array-max", min=1, help="Maximum concurrent array tasks."),
    ] = 20,
    log_dir: Annotated[
        Path,
        typer.Option("--log-dir", help="Slurm stdout and stderr directory."),
    ] = Path("slurm-logs"),
    setup_file: Annotated[
        Path | None,
        typer.Option("--setup-file", help="Shell file sourced before each task."),
    ] = None,
    module: Annotated[
        list[str] | None,
        typer.Option("--module", help="Environment module to load; may be repeated."),
    ] = None,
    keep_script: Annotated[
        Path | None,
        typer.Option("--keep-script", help="Write the Slurm array script to this path."),
    ] = None,
) -> None:
    """Submit a run list as one Slurm array job."""
    try:
        result = submit_jobs(
            run_list,
            account=account,
            partition=partition,
            time=time,
            memory=memory,
            cpus=cpus,
            array_max=array_max,
            log_dir=log_dir,
            setup_file=setup_file,
            modules=tuple(module or ()),
            keep_script=keep_script,
        )
    except (OSError, StepBySampleError) as exc:
        _abort(exc)

    console = _console()
    table = Table(box=box.ROUNDED, show_header=False, title="Slurm submission")
    table.add_column("Setting", style="bold")
    table.add_column("Value")
    table.add_row("Array entries", str(result.entries))
    table.add_row("Array script", Text(str(result.array_script)))
    table.add_row("Scheduler", Text(result.output or "submitted"))
    console.print(table)


_STATE_STYLE = {
    SampleState.done: "green",
    SampleState.failed: "bold red",
    SampleState.pending: "yellow",
    SampleState.other: "yellow",
    SampleState.conflict: "bold magenta",
    SampleState.extra: "cyan",
}


@app.command()
def status(
    output_dir: Annotated[Path, typer.Argument(help="Per-sample output directory.")],
    input_dir: Annotated[
        Path | None,
        typer.Option("--input-dir", help="Expected sample directory for pending/extra detection."),
    ] = None,
    show_all: Annotated[
        bool,
        typer.Option("--all", help="Show successful samples as well as problems."),
    ] = False,
    fail_on_problems: Annotated[
        bool,
        typer.Option(help="Exit nonzero when failures or marker conflicts exist."),
    ] = False,
) -> None:
    """Summarize sample completion markers and missing outputs."""
    try:
        statuses = inspect_status(output_dir, input_dir=input_dir)
    except (OSError, StepBySampleError) as exc:
        _abort(exc)
    counts = status_counts(statuses)
    console = _console()

    details = Table(box=box.ROUNDED, title="Sample status")
    details.add_column("Sample", style="bold")
    details.add_column("State")
    details.add_column("Detail", overflow="fold")
    visible = (
        statuses
        if show_all
        else tuple(item for item in statuses if item.state is not SampleState.done)
    )
    for item in visible:
        details.add_row(
            Text(item.sample),
            Text(item.state.value.upper(), style=_STATE_STYLE[item.state]),
            Text(item.detail),
        )
    if visible:
        console.print(details)
    elif statuses:
        console.print("[bold green]All samples are complete.[/bold green]")

    summary = Table(box=box.SIMPLE_HEAVY, title="Summary")
    summary.add_column("Done", justify="right", style="green")
    summary.add_column("Failed", justify="right", style="red")
    summary.add_column("Pending/other", justify="right", style="yellow")
    summary.add_column("Conflicts", justify="right", style="magenta")
    if input_dir is not None:
        summary.add_column("Extra", justify="right", style="cyan")
    row = [
        str(counts[SampleState.done]),
        str(counts[SampleState.failed]),
        str(counts[SampleState.pending] + counts[SampleState.other]),
        str(counts[SampleState.conflict]),
    ]
    if input_dir is not None:
        row.append(str(counts[SampleState.extra]))
    summary.add_row(*row)
    console.print(summary)
    if fail_on_problems and (counts[SampleState.failed] or counts[SampleState.conflict]):
        raise typer.Exit(1)


@app.command()
def reset(
    output_dir: Annotated[Path, typer.Argument(help="Per-sample output directory.")],
    clean_outputs: Annotated[
        bool,
        typer.Option(help="Remove partial outputs while preserving run.log."),
    ] = False,
    dry_run: Annotated[
        bool,
        typer.Option(help="Preview changes without modifying files."),
    ] = False,
    force_busy: Annotated[
        bool,
        typer.Option(help="Reset samples even when a .running lock exists."),
    ] = False,
) -> None:
    """Prepare failed samples to be selected again as unfinished."""
    try:
        result = reset_failed(
            output_dir,
            clean_outputs=clean_outputs,
            dry_run=dry_run,
            force_busy=force_busy,
        )
    except (OSError, StepBySampleError) as exc:
        _abort(exc)
    console = _console()
    table = Table(box=box.ROUNDED, title="Reset preview" if dry_run else "Reset failed samples")
    table.add_column("Sample", style="bold")
    table.add_column("Action")
    for item in result.items:
        style = "yellow" if item.action.startswith("skipped") else "green"
        table.add_row(Text(item.sample), Text(item.action, style=style))
    if result.items:
        console.print(table)
    else:
        console.print("[green]No failed samples found.[/green]")
    if dry_run:
        console.print(f"Would reset: [bold]{result.found - result.busy}[/bold]")
    else:
        console.print(f"Reset: [bold green]{result.reset}[/bold green]")
    if result.busy:
        console.print(f"Skipped active samples: [bold yellow]{result.busy}[/bold yellow]")
        raise typer.Exit(1)


@app.command()
def validate(
    input_dir: Annotated[Path, typer.Argument(help="Directory containing one folder per sample.")],
) -> None:
    """Check an input directory before generating jobs."""
    try:
        result = validate_inputs(input_dir)
    except (OSError, StepBySampleError) as exc:
        _abort(exc)
    console = _console()
    console.print("[bold green]Valid input directory[/bold green]", Text(str(result.input_dir)))
    summary = Table(box=box.ROUNDED, show_header=False)
    summary.add_column("Metric", style="bold")
    summary.add_column("Count", justify="right")
    summary.add_row("Sample directories", str(len(result.samples)))
    summary.add_row("Non-directory items", str(len(result.non_directories)))
    summary.add_row("Empty samples", str(len(result.empty_samples)))
    summary.add_row("Hidden samples", str(len(result.hidden_samples)))
    console.print(summary)

    warnings: Counter[str] = Counter()
    for name in result.non_directories:
        warnings[f"ignored non-directory: {name}"] += 1
    for name in result.empty_samples:
        warnings[f"empty sample: {name}"] += 1
    for name in result.hidden_samples:
        warnings[f"hidden sample: {name}"] += 1
    for warning in warnings:
        console.print("[yellow]Warning:[/yellow]", Text(warning))
