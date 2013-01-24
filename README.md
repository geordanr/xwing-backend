(Yet Another) Backend for the X-Wing Miniatures Squad Builder
=============================================================

Backend JS API
--------------
### `.save(serializedSquad, id=null, name, faction, additional_data={}, cb)`
Save serialized squad to backend with given name and additional data.

If `id` is null, saves a new squad.  Otherwise, saves squad to `id`.

`name` must be unique among user squads.

`additional_data` includes stuff like

    description
    points
    cards used

When finished, calls `cb({ id: ..., success: true|false })`.

### `.delete(id, cb)`
Deletes squad with given `id` from backend.

When finished, calls `cb({ success: true|false })`.

### `.list(builder, all=false)`
Lists all saved squads of given `builder.faction` for this user.  Description is a summary of pilots, etc.

Displays modal of squads for user to select.

If `all` is `true`, lists squads for everyone in the system.

### `.authenticate(cb)`
Called by the login child window when OAuth authentication is complete.  Confirms authentication with the server and calls `cb` when done.  Sets internal authentication state.

Returns true if authenticated.

### `.login()`
Starts login process.

### `.logout()`
Logs out.  Clears internal authentication state.

Backend Server Endpoints
------------------------
### `GET /`
Doesn't really do anything of note.

Returns 200.

### `GET /methods`
Get list of OAuth methods supported.

Returns `{ methods: [ 'foo', 'bar', ... ] }`

### `POST /auth/METHOD`
Logs in using OAuth for given method.  Begins OAuth token exchange redirection dance.

### `GET /auth/METHOD/callback`
Callback from successful OAuth.  Signals `window.parent` that authorization is complete.

### `GET /auth/logout`
Invalidate user session.  Returns 200.

### `GET /squads/list`
Fetch list of squads for authenticated user.  This is what `list()` connects to.

Returns `{ "Rebel Alliance": [ ... ], "Galactic Empire": [ ... ] }`.

Each item in the list is `{ name: ..., id: ..., points: ..., description: ..., additional_data: ... }`.

### `GET /all`
Fetch list of squads for all users.  This is what `list()` connects to.  Unprotected.

### `PUT /squads/new`
Save new squad.

PUT data: `{ name: ..., serialized: ..., faction: ..., additional_data: {...} }`

Returns `{ id: ..., success: true|false, error: ... }`

### `POST /squads/ID`
Update squad.

POST data `{ name: ..., serialized: ..., faction: ..., additional_data: {...} }`

Returns: `{ id: ..., success: true|false, error: ... }`

### `POST /squads/namecheck`
Check if a squad name is available for use by user.

POST data `{ name: ... }`

Returns: `{ available: true|false }`

### `DELETE /squads/ID`
Delete squad.

Returns `{ success: true|false, error: ... }`.

### `GET /ping`
Used to check session authentication.  Returns `{ success: true }` or 403.
