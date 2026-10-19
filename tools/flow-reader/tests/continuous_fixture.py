"""Manual browser fixture: normal Reader API with frequent transport boundaries.

First run with --write-fixture DIRECTORY, then use the normal serve.py arguments
with that directory as --root. Only this test helper reduces the section size.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def write_fixture(directory):
    directory.mkdir(parents=True, exist_ok=True)
    source = ['#import "@preview/mannot:0.4.0": mark, annot\n#set heading(numbering: "1")\n']
    for chapter in range(14):
        source.append(f'= Continuous chapter {chapter} <chapter-{chapter}>\n\n'
                      'Jump to #link(<chapter-13>)[the last chapter] '
                      'or #link(<chapter-0>)[the first chapter].\n\n')
        for paragraph in range(9):
            source.append(f'Passage {chapter}.{paragraph}: Continuous reading keeps the selected '
                          'sentence visible while neighboring content arrives. Scroll down to '
                          'continue without a next-section button.\n\n')
        source.append(f'$ mark(x, tag: #<term-{chapter}>) + y = z '
                      f'#annot(<term-{chapter}>)[Explanation for chapter {chapter}.] $\n\n')
    # Never overwrite an existing source file, including a hand-edited test case.
    with (directory / "main.typ").open("x") as output:
        output.write("".join(source))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--write-fixture":
        write_fixture(Path(sys.argv[2]))
    else:
        from flow_reader.server import cli as serve
        from flow_reader.server import state as state_module
        from flow_reader.document.sections import split_document
        state_module.split_document = lambda source, revision: split_document(
            source, revision, max_chars=4000, max_blocks=14)
        serve.main()
