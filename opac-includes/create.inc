<!-- Error Handling -->
[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        <li>[% whole.status %]</li>
        <li>[% whole.message %]</li>
    </ol>
[% END %]

[% IF whole.stage == "search_form" %]
    <h2>Search a dummy request</h2>
    <form class="validated" method="post" action="/cgi-bin/koha/opac-illrequests.pl">
        <input type="hidden" name="stage" value="[% whole.stage %]"/>
        <input type="hidden" name="method" value="[% whole.method %]"/>
        <input type="hidden" name="op" value="[% whole.method %]"/>
        <input name="backend" id="method" value="[% whole.value.other.backend %]" type="hidden"/>
        <fieldset class="rows">
            <ol>
                <li>
                    <label class="required" for="search">Search string: </label>
                    <input class="required" required="required" type="text" name="search" value="" />
                    <span class="required">Required</span>
                </li>
                <li>
                    <label class="required" for="branchcode">Pickup branch: </label>
                    <select class="required" required="required" id="branchcode" name="branchcode">
                        [% FOREACH branch IN branches %]
                            <option value="[% branch.branchcode %]">
                        [% branch.branchname %]
                            </option>
                        [% END %]
                    </select>
                    <span class="required">Required</span>
                </li>
                <li>
                    <label class="required" for="medium">Request type: </label>
                    <select class="required" required="required" id="medium" name="medium">
                        [% FOREACH medium IN media %]
                            <option value="[% medium %]">[% medium %]</option>
                        [% END %]
                    </select>
                    <span class="required">Required</span>
                </li>
            </ol>
        </fieldset>
        <fieldset class="action">
            <input type="submit" value="Search"/>
            <a class="cancel" href="/cgi-bin/koha/opac-illrequests.pl">Cancel</a>
        </fieldset>
    </form>

[% ELSIF whole.stage == "search_results" %]
    <h2>Select a dummy request</h2>
    [% IF whole.value.candidates %]
        <table class="table table-bordered table-striped">
            <thead>
                <tr>
                    <th id="id">ID</th>
                    <th id="title">Title</th>
                    <th id="author">Author</th>
                    <th id="select">Select?</th>
                </tr>
            </thead>
            <tbody>
                [% FOREACH candidate IN whole.value.candidates %]
                    <tr>
                        <td>[% candidate.id %]</td>
                        <td>[% candidate.title %]</td>
                        <td>[% candidate.author %]</td>
                        [% target = "/cgi-bin/koha/opac-illrequests.pl"
                        _ "?method=" _ whole.method
                        _ "&amp;stage=" _ whole.stage
                        _ "&amp;backend=" _ whole.value.backend
                        _ "&amp;branchcode=" _ whole.value.branchcode
                        _ "&amp;medium=" _ whole.value.medium
                        _ "&amp;id=" _ candidate.id %]
                        <td>
                            <a class="btn btn-sm btn-default" href="[% target %]">Request this item</a>
                        </td>
                    </tr>
                [% END %]
            </tbody>
        </table>
    [% ELSE %]
        <p>We have no results</p>
    [% END %]

[% ELSE %]
    <p>We encountered an unexpected situation</p>

[% END %]
