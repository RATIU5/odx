// Aliases through an import odx doesn't follow, where each name lacks the case of every kind but
// one, beside a plain constant that lacks its own. This file needs only to parse.
package unfollowed

import "shared:foo"

thing :: foo.Bar
Thing :: foo.Bar
called :: foo.Bar(3)
Called :: foo.Bar(3)

limit :: 5
