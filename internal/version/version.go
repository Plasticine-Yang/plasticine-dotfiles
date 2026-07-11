package version

import "fmt"

var (
	version    = "dev"
	commit     = "unknown"
	commitTime = "unknown"
)

type Info struct {
	Version    string
	Commit     string
	CommitTime string
}

func Current() Info {
	return Info{
		Version:    version,
		Commit:     commit,
		CommitTime: commitTime,
	}
}

func (info Info) String() string {
	return fmt.Sprintf("plasticine %s commit=%s commit_time=%s", info.Version, info.Commit, info.CommitTime)
}
