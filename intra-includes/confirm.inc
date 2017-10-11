<!-- Error Handling -->
[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        <li>[% whole.status %]</li>
        <li>[% whole.message %]</li>
    </ol>
[% END %]

[% IF whole.stage == "confirm" %]
    <!-- This should not happen -->
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
