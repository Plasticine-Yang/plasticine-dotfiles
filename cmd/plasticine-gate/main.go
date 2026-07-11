package main

import (
	"fmt"
	"os"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) < 1 {
		usage()
		return 2
	}
	switch args[0] {
	case "tool-lock":
		if len(args) != 2 {
			usage()
			return 2
		}
		lock, err := release.LoadToolLock(args[1])
		if err != nil {
			fmt.Fprintf(os.Stderr, "load tool lock: %v\n", err)
			return 1
		}
		if err := release.ValidateToolLock(lock); err != nil {
			fmt.Fprintf(os.Stderr, "validate tool lock: %v\n", err)
			return 1
		}
		fmt.Println("tool lock: ok")
		return 0
	case "artifacts":
		if len(args) != 2 {
			usage()
			return 2
		}
		report, err := release.ValidateReleaseArtifacts(args[1], platform.SupportedArtifactTargets())
		if err != nil {
			fmt.Fprintf(os.Stderr, "validate artifacts: %v\n", err)
			return 1
		}
		fmt.Printf("artifacts: %d raw executables\n", len(report.Artifacts))
		fmt.Printf("manifest: %s\n", report.Manifest)
		return 0
	case "compare-manifests":
		if len(args) != 3 {
			usage()
			return 2
		}
		if err := release.CompareChecksumManifests(args[1], args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "%v\n", err)
			return 1
		}
		fmt.Println("reproducibility: ok")
		return 0
	default:
		usage()
		return 2
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: plasticine-gate <tool-lock PATH|artifacts DIR|compare-manifests LEFT RIGHT>")
}
