# Nodus examples

[`tasks/`](tasks/) is the executable reference application for Nodus. It uses
the package through a local path and exercises generated persistence, typed
queries, mutation drafts, routing, synchronization, collaboration, activity,
ordering, archiving, and soft deletion.

Run it without external credentials:

```sh
git clone git@github.com:sidux/nodus.git
cd nodus/example/tasks
flutter pub get
flutter run --dart-define=ALLOW_IN_MEMORY_DEMO=true
```

The demo creates its seed workspace through the generated production APIs and
shows durable pending synchronization work. See the
[Tasks guide](tasks/README.md) for its architecture and verification commands.
