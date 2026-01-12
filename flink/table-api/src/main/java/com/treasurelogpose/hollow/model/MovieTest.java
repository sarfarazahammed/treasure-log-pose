package com.treasurelogpose.hollow.model;

import com.netflix.hollow.core.write.objectmapper.HollowPrimaryKey;

@HollowPrimaryKey(fields = "id")
public class MovieTest {
    public long id;
    public String title;
    public int releaseYear;

    public MovieTest(long id, String title, int releaseYear) {
        this.id = id;
        this.title = title;
        this.releaseYear = releaseYear;
    }
}
