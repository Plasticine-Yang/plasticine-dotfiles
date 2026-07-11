# Use one Managed Block for the SSH include

The GitHub SSH Component will own a complete `~/.plasticine/config/ssh/github.conf` fragment and one stably marked Include block inside `~/.ssh/config`, preserving all bytes outside that block. First insertion into an existing unmanaged file remains a Conflict requiring adoption and a whole-file backup; missing, duplicate, or malformed markers block later Apply rather than triggering a guessed merge. This is the sole initial exception to whole-path ownership.
