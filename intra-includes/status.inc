<!-- Error Handling -->
[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        <li>[% whole.status %]</li>
        <li>[% whole.message %]</li>
    </ol>
[% END %]

[% IF whole.stage == "status" %]
    <h2>Current status of ILL request</h2>
    <h3>Status</h3>
    <fieldset class="rows">
        <ol>
            <li class="illrequest_id">
                <label class="illrequest_id">Our ID:</label>
                [% whole.value.id %]
            </li>
            <li class="title">
                <label class="title">Title:</label>
                [% whole.value.title %]
            </li>
            <li class="author">
                <label class="author">Author:</label>
                [% whole.value.author %]
            </li>
            <li class="status">
                <label class="status">Status:</label>
                [% whole.value.status %]
            </li>
        </ol>
    </fieldset>

    <h3>Request details</h3>
    <fieldset class="rows">
        <ol>
            <li class="borrower_id">
                <label class="borrower_id">Borrower:</label>
                [% borrowerlink = "/cgi-bin/koha/members/moremember.pl"
                _ "?borrowernumber=" _ brw.borrowernumber %]
                <a href="[% borrowerlink %]" title="View borrower details">
                    [% request.patron.firstname _ " "
                    _ request.patron.surname _ ", "
                    _ request.patron.cardnumber %]
                </a>
            </li>
            <li class="biblio_id">
                <label class="biblio_id">Biblio number:</label>
                [% request.biblio_id %]
            </li>
            <li class="branch_id">
                <label class="branch_id">Branch number:</label>
                [% request.branch_id %]
            </li>
            <li class="status">
                <label class="status">Status:</label>
                [% request.status %]
            </li>
            <li class="updated">
                <label class="updated">Last updated:</label>
                [% request.updated %]
            </li>
            <li class="medium">
                <label class="medium">Request type:</label>
                [% request.medium %]
            </li>
            <li class="cost">
                <label class="cost">Cost:</label>
                [% request.cost %]
            </li>
            <li class="req_id">
                <label class="req_id">Request number:</label>
                [% request.id_prefix _ request.illrequest_id %]
            </li>
            <li class="notesstaff">
                <label class="notes_staff">Staff notes:</label>
                <pre>[% request.notesstaff %]</pre>
            </li>
            <li class="notesopac">
                <label class="notes_opac">Staff notes:</label>
                <pre>[% request.notesstaff %]</pre>
            </li>
        </ol>
    </fieldset>

    [% commitlink = here_link _ "?method=" _ whole.method
    _ "&amp;stage=" _ whole.stage
    _ "&amp;illrequest_id=" _ request.illrequest_id %]
    <p>
        <a href="[% commitlink %]" title="Return to overview.">Back to overview</a>
    </p>

[% ELSE %]
    <p>We encountered an unexpected situation</p>
    <p>
        <a href="[% here_link %]" title="Return to overview.">Back to overview</a>
    </p>
[% END %]
