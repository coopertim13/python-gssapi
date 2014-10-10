import six

from gssapi.raw import names as rname
from gssapi.raw import NameType
from gssapi import _utils


class Name(rname.Name):
    __slots__ = ()

    def __new__(cls, base=None, name_type=None, token=None):
        if token is not None:
            base_name = rname.importName(token, NameType.export)
        elif isinstance(base, rname.Name):
            base_name = base
        else:
            base_name = rname.importName(base, name_type)

        return super(Name, cls).__new__(cls, base_name)

    def __str__(self):
        if issubclass(str, six.text_type):
            # Python 3 -- we should return unicode
            return bytes(self).decode(_utils._get_encoding())
        else:
            # Python 2 -- we should return a string
            return self.__bytes__()

    def __unicode__(self):
        # Python 2 -- someone asked for unicode
        return self.__bytes__().encode(_utils._get_encoding())

    def __bytes__(self):
        # Python 3 -- someone asked for bytes
        return rname.displayName(self, name_type=False).name

    @property
    def name_type(self):
        return rname.displayName(self, name_type=True).name_type

    def __eq__(self, other):
        if not isinstance(other, rname.Name):
            # maybe something else can compare this
            # to other classes, but we certainly can't
            return NotImplemented
        else:
            return rname.compareName(self, other)

    def __ne__(self, other):
        return not self.__eq__(other)

    def __repr__(self):
        disp_res = rname.displayName(self, name_type=True)
        return "Name({name}, {name_type})".format(name=disp_res.name,
                                                  name_type=disp_res.name_type)

    def export(self):
        return rname.exportName(self)

    def canonicalize(self, mech_type):
        return type(self)(rname.canonicalizeName(self, mech_type))

    def __copy__(self):
        return type(self)(rname.duplicateName(self))

    def __deepcopy__(self, memo):
        return type(self)(rname.duplicateName(self))
