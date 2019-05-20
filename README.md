# Overview

The datalackey-prefixed commands here are intended to be run instead of running datalackey directly. Datalackey is intended to be a dumb process that just stores your data, and other progrems are meant to control it. I refer to these as controllers.

As you should specify the storage options, each of these requires either memory or directory storage be specified. Memory storage requires that all data fits in main memory at once. Directory storage allows you to shut things down and return later and still have what you were working on remain as it was.

* datalackey-shell is a shell intended to make issuing datalackey commands a bit easier. The imagined use is you can tinker with various programs with this and leave repetitive tasks to other tools.
* datalackey-fsm is intended for performing a well-known task that you specify from start to end. You could run it form within datalackey-shell and have it perform repetitive parts.
* datalackey-run is helper that takes care of running datalackey and your program as child process of datalackey, freeing your controller to deal only with communicating with datalackey.
* files2mapped and input2mapped are simple alternative to datalackey. files2mapped outputs file contents with given names that is the same as what datalackey outputs to program it runs, given input data. input2mapped does the reverse, performing what datalackey does to program output. Potentially helpful in debugging a program to be run using datalackey.

# Shell

The datalackey-sheel is intended to allow you to issue commands to datalackey interactively, rather than typing JSON-encoded arrays. That is basically all it does. If you need to write scripts that would issue commands and wait for outcomes, see datalackey-fsm. Consequently there are no control statements.

# FSM

Started life as a finite state machine to allow one to implement algorithms easily. You have states that are command lists. Signals trigger state transitions according to mapping associated with the state. The rest are additions intended to make life easier.

The files are in YAML-format. A list of mappings at top level. Each key in the mapping is a state, except for the ones listed below. You can add as many states in the same mapping as you like. They all share the three optional mappings that control state transitions:

* signal2state: signal name to next state name mapping. Missing signal for the case where command list is executed and no signal is triggered is indicated by null signal. This mapping applies only to the state it is associated with. Note that if there is no state to move to, the processing will stop, so you want ito use either this mapping or jump command.
* global_signal2state: as above but stays in effect until replaced. Has lower priority than state-specific mappings. Useful for generic error signals and such.
* label2signal: maps data label name to signal. Notification about appearance (or replacement) of this label triggers the signal. Use together with wait_data command to wait results to be stored into datalackey before moving on.

First state mapping of the first file may have only one state and that state is the initial state. State contents are a list of commands. Note that only a few commands, such as set/unset have the command and first argument (variable name) protected from variable expansion, so the command can be variable name, that is then expanded to command.

A command is a list of strings. As a short-hand, a strgin with spaces is split into a list so you can write the command into one line. If you want spaces in your variable names, see YAML documentation on how to do it.

Variable is just a name mapped to something else. When command is executed, anything in the command that matches a variable is expanded, with some exceptions such as set/unset. Hence you can assign a command into variable, and have that contain other variables etc. There is no need to explicitly as for expansion, nor is there a way to avoid it.

Variable can be treated as a stack, with push and pop. Hence you can technically achieve jump to sub-routine ("sub-state") and return from one. Tail recursion should be possible. If you are so inclined.

Commands are mainly to check for things, as the various assert-commands, print out something, wait for something, set/unset variables, run programs, feed them input and stop them, and rename/delete data. These commands are simple lists.

There are two commands that are mappings: script and ruby. The former allows you to run a script and store output to variables, with non-zero exit value triggering error signal. The ruby command allows you to run the included ruby snippet in the context of the global machine object. Hence you can add commands or do anything the current commands do not cover. Since program reads multiple files, you can separate your command-adding states for re-use into their own files. 

See test/fsm and examples directories for how to use ruby/script and how to use re-usable states, should you need them.

# Make

Given needed targets, finds their dependencies and runs commands in required order. Targets are not files nor data labels. Otherwise resembles make. Commands are mainly the same as in datalackey-fsm.

# Run

A simple tool meant only to run a controller under datalackey, such that the controller does not need to run datalackey itself but can operate as a child process. Hence you can use quick hacks and such fairly easily as long as you can communicate with datalackey.

# Helper gem

The datalackeylib is a simple gem that simplifies mapping datalackey output to something that needs to be done, allows sending stuff to datalackey, and handles running the datalackey process, if desired. A few convenience methods are also present.

You can use the DatalackeyProcess to actually run datalackey if you want, or if you run the controller under datalackey, then DatalackeyParentProcess. See datalackey-fsm for example of both.

DatalackeyIO handles reading datalackey process and sending it your commands and data. Each command is paired with PatternAction. That is a mapping from datalackey output (see output of datalackey -m --report commands) to category/action pairs you can then use in conditional statement to act accordingly. DatalackeyIO also keeps track of processes and data by tracking notifications.

# License

Copyright (C) 2019 Ismo Kärkkäinen

Licensed under Universal Permissive License. See License.txt.
