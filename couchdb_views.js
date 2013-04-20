// squads/byUserName
function(doc) {
    if (doc.type === 'squad') {
        emit([ doc.user_id, doc.name ], null);
    }
}

// squads/list
function(doc) {
    if (doc.type === 'squad') {
        emit([doc.user_id, doc.faction, doc.name], {
            serialized: doc.serialized,
            additional_data: doc.additional_data,
        });
    }
}
