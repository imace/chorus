chorus.collections.MemberSet = chorus.collections.Base.extend({
    constructorName: "MemberSet",
    model:chorus.models.User,
    urlTemplate:"workspace/{{workspaceId}}/member",

    save:function () {
        var self = this;

        Backbone.sync('update', this, {
            data:this.toUrlParams(),
            success:function (resp, status, xhr) {
                self.pagination = resp.pagination;
                var savedEvent = (resp.status == "ok") ? "saved" : "saveFailed"
                self.trigger(savedEvent);
            }
        });
    },

    toUrlParams:function () {
        return this.reduce(function (memo, model) {
            var param = "members=" + model.get("id");
            return (memo.length === 0) ? param : (memo + "&" + param)
        }, "");
    }
});
