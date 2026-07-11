package main

import (
	"flag"
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
	case "metadata":
		if len(args) != 5 {
			usage()
			return 2
		}
		if err := release.ValidateReleaseMetadata(args[1], platform.SupportedArtifactTargets(), release.BuildMetadata{
			Version:    args[2],
			Commit:     args[3],
			CommitTime: args[4],
		}); err != nil {
			fmt.Fprintf(os.Stderr, "validate metadata: %v\n", err)
			return 1
		}
		fmt.Println("metadata: ok")
		return 0
	case "publication":
		return runPublicationGate(args[1:])
	default:
		usage()
		return 2
	}
}

func runPublicationGate(args []string) int {
	flags := flag.NewFlagSet("publication", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	requiredGatesPassed := flags.Bool("required-gates-passed", true, "whether required release gates have already passed")
	existingRelease := flags.Bool("existing-release", false, "whether this release already exists")
	dirtyBuild := flags.Bool("dirty-build", false, "whether the source build is dirty")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 4 {
		usage()
		return 2
	}
	plan, err := release.PlanPublication(release.PublicationRequest{
		Tag:                 flags.Arg(0),
		Version:             flags.Arg(1),
		AssetDir:            flags.Arg(2),
		InstallScriptPath:   flags.Arg(3),
		RequiredGatesPassed: *requiredGatesPassed,
		ExistingRelease:     *existingRelease,
		DirtyBuild:          *dirtyBuild,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "publication plan: %v\n", err)
		return 1
	}
	fmt.Printf("publication: %s %s\n", plan.Tag, plan.Channel)
	fmt.Printf("version-install: %s\n", plan.VersionInstallURL)
	if plan.UpdatesLatestStable {
		fmt.Printf("latest-stable: %s\n", plan.LatestStableInstallURL)
	}
	return 0
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: plasticine-gate <tool-lock PATH|artifacts DIR|compare-manifests LEFT RIGHT|metadata DIR VERSION COMMIT COMMIT_TIME|publication [FLAGS] TAG VERSION ASSET_DIR INSTALL_SH>")
}
