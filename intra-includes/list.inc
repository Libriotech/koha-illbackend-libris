<!-- Error Handling -->
[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        <li>[% whole.status %]</li>
        <li>[% whole.message %]</li>
    </ol>
[% END %]

<h2>Currently active requests</h2>
[% IF whole.value %]
    <table>
        <thead>
            <tr>
                <th id="illrequest_id">Our ID</th>
                <th id="id">Their ID</th>
                <th id="title">Title</th>
                <th id="author">Author</th>
                <th id="status">Status</th>
                <th id="cost">Cost</th>
            </tr>
        </thead>
        <tbody>
            [% FOREACH illrequest_id IN whole.value.keys %]
                <tr>
                    <td>[% illrequest_id %]</td>
                    <td>[% whole.value.item(illrequest_id).id %]</td>
                    <td>[% whole.value.item(illrequest_id).title %]</td>
                    <td>[% whole.value.item(illrequest_id).author %]</td>
                    <td>[% whole.value.item(illrequest_id).status %]</td>
                    <td>[% whole.value.item(illrequest_id).cost %]</td>
                </tr>
            [% END %]
        </tbody>
    </table>

[% commitlink = here_link _ "?method=" _ whole.method "&amp;stage=" _ whole.stage %]
<p>
    <a href="[% commitlink %]" title="Return to overview.">Back to overview</a>
</p>

[% ELSE %]
    <p>We have no currently active requests.</p>
[% END %]
